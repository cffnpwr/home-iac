# kubesealでのSealedSecretの作成

この手順書は`kubeseal`でSealedSecretを作成するときの手順を説明する。

- SealedSecretの追加
- キーの追加・値の更新
- 鍵が更新されたときの再暗号化

## Prerequisites

- `mise install`でツールをインストール済み
- 鍵が更新されたときの再暗号化では`kubectl`でクラスタに接続できる

暗号化にはリポジトリの`kubernetes/apps/sealed-secrets/cert.pem`を使う。
この証明書はsealed-secrets controllerが新しい鍵を追加したときに実行される`.github/workflows/reseal-sealed-secrets.yaml`のworkflowが更新する。

各手順では次の変数を使う。

```sh
cert=kubernetes/apps/sealed-secrets/cert.pem
export cert_sha256=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d = -f 2 | tr -d : | tr '[:upper:]' '[:lower:]')
```

## SealedSecretの追加

SealedSecretは単一の値からもSecretのマニフェストからも作成できる。
どちらの方法でも、暗号化に使った証明書のSHA-256ハッシュ値を`home-iac/cert-sha256`アノテーションに記録する。

### 単一の値から作成する

コマンドの`<value-command>`は値を標準出力へ書き出すコマンドで置き換える。
`<value-command>`の出力は末尾の改行も含めて値になる。
値は標準入力で渡すためコマンドラインの引数に平文を含めずに済む。

1. 値を暗号化しSealedSecretのファイルを作成する

   ```sh
   <value-command> \
     | kubectl create secret generic <name> --namespace <namespace> --from-file=<key>=/dev/stdin --dry-run=client -o json \
     | kubeseal --cert "$cert" --format json \
     | yq -p json -o yaml '.metadata.annotations["home-iac/cert-sha256"] = strenv(cert_sha256)' \
     > kubernetes/apps/<app>/<name>.yaml
   ```

2. 2つ目以降のキーは[キーの追加・値の更新](#キーの追加値の更新)の手順で追加する
3. 作成したファイルを`kubernetes/apps/<app>/kustomization.yaml`の`resources`に追加する

### Secretのマニフェストから作成する

複数のキーをまとめて暗号化する場合はSecretのマニフェストを`kubeseal`に渡す。

1. Secretのマニフェストを作成する。
   値は`stringData`に平文で書くか`data`にBase64で書く

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: <name>
     namespace: <namespace>
   stringData:
     <key>: <value>
   ```

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: <name>
     namespace: <namespace>
   data:
     <key>: <base64-encoded-value>
   ```

2. マニフェストを暗号化しSealedSecretのファイルを作成する

   ```sh
   kubeseal --cert "$cert" --format json < <secret-file> \
     | yq -p json -o yaml '.metadata.annotations["home-iac/cert-sha256"] = strenv(cert_sha256)' \
     > kubernetes/apps/<app>/<name>.yaml
   ```

3. マニフェストは平文の値を含むため削除する
4. 作成したファイルを`kubernetes/apps/<app>/kustomization.yaml`の`resources`に追加する

## キーの追加・値の更新

1. 対象のファイルの`home-iac/cert-sha256`が`$cert_sha256`と一致することを確認する。
   1つのファイルの中で暗号化に使った証明書を揃えるため、一致しない場合は先に[鍵が更新されたときの再暗号化](#鍵が更新されたときの再暗号化)を行なう

   ```sh
   yq '.metadata.annotations["home-iac/cert-sha256"]' kubernetes/apps/<app>/<name>.yaml
   echo "$cert_sha256"
   ```

2. 値を暗号化しファイルの`spec.encryptedData`に書き込む。
   既存のキーを指定した場合は値を置き換える。
   `<value-command>`は[単一の値から作成する](#単一の値から作成する)と同じく置き換える

   ```sh
   export encrypted=$(<value-command> \
     | kubeseal --raw --cert "$cert" --namespace <namespace> --name <name> --from-file=/dev/stdin)
   yq -i '.spec.encryptedData["<key>"] = strenv(encrypted)' kubernetes/apps/<app>/<name>.yaml
   ```

3. 変更をmainにマージしArgo CDが同期するまで待つ
4. Podは起動した後に変わったSecretの値を環境変数に反映しないため、値を更新した場合はSecretを環境変数で参照するPodを再起動する。
   Reloaderの対象のSecretはReloaderがPodを再起動する。
   Deployment・DaemonSet・StatefulSetのPodは`kubectl rollout restart`で再起動する

   ```sh
   kubectl rollout restart -n <namespace> <deployment|daemonset|statefulset>/<name>
   ```

   `kubectl rollout restart`はそれ以外のリソースに対応していない。
   ReplicaSet等のPodは削除して作り直す。
   ReplicaSetは削除されたPodの代わりに新しいPodを作成する

   ```sh
   kubectl delete pod -n <namespace> -l <label-selector>
   ```

## 鍵が更新されたときの再暗号化

sealed-secrets controllerが新しい鍵を追加すると、再暗号化するworkflowが`cert.pem`を更新するPRを作成する。
このPRをマージした後に`kubeseal`で作成したSealedSecretを新しい鍵で再暗号化する。
古い鍵を削除するJobはすべてのSealedSecretを最新の鍵で復号できる場合だけ古い鍵を削除する。
このため再暗号化した変更がクラスタに同期されるまで古い鍵は削除されない。

1. `sealed-secrets:reseal`タスクを実行する。
   タスクは`kubernetes/`以下のすべてのSealedSecretを対象にする。
   このうち`home-iac/cert-sha256`がcontrollerの最新の証明書と一致しないファイルを再暗号化する。
   再暗号化はcontrollerが行なうためクラスタへの接続が必要である

   ```sh
   mise run sealed-secrets:reseal
   ```

2. 変更したファイルをコミットしmainにマージする
