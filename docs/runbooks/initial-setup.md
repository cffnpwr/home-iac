# クラスタの初回構築

この手順書はクラスタを初めて構築するときの手順を説明する。
次の順に実行する。

1. plan用・apply用のGitHub Appの準備
2. bootstrapの構築
3. reseal用・backup用のGitHub Appの作成
4. クラスタの構築
5. ローカルサーバーの参加
6. netbirdの設定

## Prerequisites

- `mise install`でツールをインストール済み
- [bootstrap用のトークン](./terraform.md#bootstrap用のトークン)を作成済み
- `terraform-apply`が使う、読み書きできるCloudflareのAPIトークンをダッシュボードで作成済み
  - CIのapplyはこのトークンからS3 backendの認証情報を作る
  - このためトークンには`home-iac-tfstate`のR2 Bucketを読み書きする権限も付与する
- AccessでGoogle Workspaceを使うためのOAuthクライアントをGoogle Cloudのコンソールで作成済み

## plan用・apply用のGitHub Appの準備

plan用・apply用のGitHub AppはdotfilesのCIと共有する。
GitHub Appの種類と権限は[CIでのplan・apply](./terraform.md#ciでのplanapply)に記載している。
`terraform/bootstrap/`はGitHub AppのClient IDと秘密鍵を`terraform-plan`・`terraform-apply`のenvironmentに登録する。
このため、bootstrapを構築する前にGitHub Appを`home-iac`へインストールし、Client IDと秘密鍵を用意する。
次の手順は`plan`・`apply`の種類ごとに実行する。

GitHub Appがない場合はcffnpwr/actionsの[create-github-app](https://github.com/cffnpwr/actions/tree/main/modules/github-app)の手順で作成する。
`create-github-app`の`--repo`に`cffnpwr/home-iac`を指定し、GitHub Appを`home-iac`にインストールする。
`create-github-app`が表示したClient IDと、定義ファイルの`path`に書き込んだ秘密鍵を[bootstrapの構築](#bootstrapの構築)で使う。

GitHub Appが既にある場合は次の手順で`home-iac`にインストールし、Client IDと秘密鍵を用意する。

1. GitHub Appのinstallationに`home-iac`を追加する
   1. GitHubの「Settings」で「Applications」を開き、「Installed GitHub Apps」を選ぶ
   2. 対象のGitHub Appの「Configure」を選ぶ
   3. 「Repository access」で「Only select repositories」を選び、「Select repositories」で`home-iac`を追加する
   4. 「Save」を選ぶ
2. GitHub Appの設定画面の「Key pairs」で「New key」を選び、秘密鍵を作成する
3. GitHub Appの設定画面に表示されたClient IDと、手順2で作成した秘密鍵を[bootstrapの構築](#bootstrapの構築)で使う

## bootstrapの構築

`terraform/bootstrap/`はtfstate用のR2 Bucketと、CIのjobが使う認証情報を作成する。
bootstrapのstateを置くBucketもbootstrap自身が作成するため、初回はローカルにstateを作成してから移行する。

1. SSE-Cの鍵を生成し、ageで暗号化して`terraform/bootstrap/sse-customer-key.age`に書き込む。
   宛先は`kubernetes/apps/sealed-secrets-backup/recipients.yaml`の`recipients.txt`である。
   生成した`sse-customer-key.age`はコミットする

   ```sh
   mise run tf:bootstrap:generate-sse-customer-key
   ```

2. [`terraform/bootstrap/`の環境変数](./terraform.md#terraformbootstrapの環境変数)を設定する。
   netbirdのPATはクラスタの構築後に作成するため、`TF_VAR_netbird_pat_read_only`・`TF_VAR_netbird_pat_read_write`には空文字列を設定する。
   `TF_VAR_plan_app_*`・`TF_VAR_apply_app_*`には[plan用・apply用のGitHub Appの準備](#plan用apply用のgithub-appの準備)で用意したClient IDと秘密鍵を設定する
3. `terraform/bootstrap/backend_override.tf`に次の内容を記載する

   ```hcl
   terraform {
     backend "local" {}
   }
   ```

4. bootstrapをapplyする

   ```sh
   mise run tf:bootstrap init
   mise run tf:bootstrap plan
   mise run tf:bootstrap apply
   ```

5. `terraform/bootstrap/backend_override.tf`を削除する
6. stateをR2 Bucketへ移行し、ローカルのstateを削除する

   ```sh
   mise run tf:bootstrap init -migrate-state
   rm -f terraform/bootstrap/terraform.tfstate terraform/bootstrap/terraform.tfstate.backup
   ```

7. Vultrのコンソールで、bootstrapで作成したservice userのAPIキーをすべてのIPアドレスから使えるようにする。
   VultrではAPIキーを使えるIPアドレスがユーザーごとに制限される。
   Terraformのproviderはこの設定を管理できない。
   GitHub-hosted runnerのIPアドレスは実行のたびに変わるため、すべてのIPアドレスを許可する。
   次の操作を`terraform-plan`・`terraform-apply`のservice userごとに行なう
   1. 上部のナビゲーションバーで組織の名前を選び、Manage Organizationを開く
   2. Usersで対象のservice userを選ぶ
   3. API AccessのAccess Control Listで、Any IPv4・Any IPv6を有効にする

## reseal用・backup用のGitHub Appの作成

reseal用のGitHub AppはSealedSecretを再暗号化するworkflowが使う。
backup用のGitHub AppはSealed Secretsの鍵を退避するJobが使う。
GitHub Appの種類と権限は[CIでのplan・apply](./terraform.md#ciでのplanapply)に記載している。
2つのGitHub Appを作成するタスクはbootstrapで作成したenvironmentと証明書を使うため、bootstrapを構築した後に実行する。
次の手順は`reseal`・`backup`の種類ごとに実行する。

1. タスクを実行する。
   タスクはGitHub Appを登録する画面のURLを表示し、ブラウザで開く。
   ブラウザが開かない場合は、表示されたURLを手動で開く。
   `backup`では`SEALED_SECRETS_CERT_FILE`にbootstrapが出力した`sealed_secrets_cert`を書いたファイルを指定する。
   `SEALED_SECRETS_CERT_FILE`の相対パスはリポジトリのルートを基準にする

   ```sh
   mise run github:create-app:<種類>
   ```

2. ブラウザでGitHub Appの名前を確認してCreate GitHub Appを選ぶ
3. タスクが表示するインストール画面で`home-iac`だけにインストールする。
   `reseal`ではタスクがインストールを確認した後にClient IDと秘密鍵をenvironmentへ登録する。
   `backup`ではタスクがClient IDと秘密鍵を`kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml`のSealedSecretに封入する

タスクはslug・App ID・Client IDだけを出力し、秘密鍵は出力しない。
登録済みのClient IDを置き換える場合は`--force`を指定する。

### 非GUI環境での実行

GitHubはGitHub Appを登録した後にブラウザを`http://127.0.0.1:<ポート>/callback`へリダイレクトする。
このURLはタスクを実行するホストで待ち受けている。
SSH接続先のホストでタスクを実行する場合は、手元のブラウザからホストのポートへ接続できるようにポートを転送する。

1. ポートを転送してホストに接続する

   ```sh
   ssh -L 8080:127.0.0.1:8080 <ホスト>
   ```

2. 転送したポートを`--listen-port`に指定してタスクを実行する

   ```sh
   mise run github:create-app:<種類> --listen-port 8080
   ```

3. タスクが表示したURLを手元のブラウザで開き、[reseal用・backup用のGitHub Appの作成](#reseal用backup用のgithub-appの作成)の手順2から続ける

## クラスタの構築

`terraform/`の初回のapplyは手元で実行する。
CIのjobはクラスタ上で動作するnetbirdを経由してクラスタに接続するため、クラスタの構築前には接続できない。
[`terraform/`の環境変数](./terraform.md#terraformの環境変数)を設定してから次の手順を実行する。
`CLOUDFLARE_API_TOKEN`は`terraform-apply`のトークンに置き換える。
bootstrap用のトークンは`BOOTSTRAP_CLOUDFLARE_API_TOKEN`に設定する。

1. RPi4用のイメージのURLを確定させる。
   URLはImage Factoryに登録したschematicのIDから決まるため、schematicだけを先に作成し、表示される`urls.disk_image`を参照する

   ```sh
   mise run tf apply -target=module.rpi4.data.talos_image_factory_urls.this
   mise run tf state show module.rpi4.data.talos_image_factory_urls.this
   ```

2. イメージをダウンロード・展開し、SDカードへ書き込む

   ```sh
   curl -LO <手順1で得たURL>
   xz -d metal-arm64.raw.xz
   sudo dd if=metal-arm64.raw of=<SDカードのデバイス> conv=fsync bs=4M
   ```

3. SDカードをRPi4に挿して起動する。
   RPi4はschematicのカーネル引数に設定した静的IPアドレスで起動し、machine configの適用を待つ
4. `terraform apply`でRPi4へmachine configを適用してクラスタをbootstrapし、Vultr上にworkerを作成する

   ```sh
   mise run tf apply
   ```

5. talosconfigを取得する

   ```sh
   mise run tf output -raw talosconfig > talosconfig
   ```

## ローカルサーバーの参加

ローカルサーバー（`terraform/main.tf`の`local.servers`）のcontrol planeは、ISOから手作業で起動して参加させる。
次の手順はサーバーごとに実行する。

1. サーバー用のISOのURLを確定させる。
   `<ホスト名>`は`local.servers`のキー（例: `cpwr-svr1`）である

   ```sh
   mise run tf apply -target='module.servers["<ホスト名>"].data.talos_image_factory_urls.this'
   mise run tf output -json server_iso_urls
   ```

2. ISOをダウンロードし、USBメモリへ書き込む

   ```sh
   curl -LO <手順1で得たURL>
   sudo dd if=metal-amd64-secureboot.iso of=<USBメモリのデバイス> conv=fsync bs=4M
   ```

3. サーバーのUEFIの設定でSecure Bootを有効にし、Setup Modeにする
4. サーバーのブートメニューでUSBメモリを選び、ISOから起動する。
   初回の起動ではEscキーでISOのブートメニューを表示し、`Enroll Secure Boot keys: auto`を選んでSecure Bootの鍵を登録する。
   サーバーはschematicのカーネル引数に設定した静的IPアドレスで起動し、machine configの適用を待つ
5. `terraform apply`でサーバーへmachine configを適用する。
   TalosはNVMeのディスクにインストールされ、再起動後にクラスタへ参加する。
   インストール後の再起動で再びISOから起動した場合は、USBメモリを取り外して再起動する

   ```sh
   mise run tf apply
   ```

## netbirdの設定

CIのjobはnetbirdのルーティングピアを経由して自宅LANのクラスタに接続する。
ルーティングピアはArgo CDが同期する`NetworkRouter`からnetbird Operatorが作成する。
クラスタの構築後に次の手順でルーティングピアとCIの接続を設定する。

1. netbirdのダッシュボードでOperator用のサービスユーザーとそのPATを作成する
2. [kubesealでのSealedSecretの作成](./sealed-secrets.md)の手順で、PATを`kubernetes/apps/netbird/netbird-mgmt-api-key.yaml`に封入する。
   Secretは`netbird` namespaceの`netbird-mgmt-api-key`とし、キー名は`NB_API_KEY`とする
3. ダッシュボードで名前とドメインがどちらも`cffnpwr-home.internal`のDNSゾーンを作成する。
   Operatorは`NetworkRouter`の`dnsZoneRef`をDNSゾーンの名前で検索する
4. Argo CDが`NetworkRouter`を同期した後に、Operatorが作成したnetworkのIDを確認する

   ```sh
   kubectl get networkrouter -n netbird cffnpwr-home -o jsonpath='{.status.networkID}'
   ```

5. ダッシュボードのNetworksで手順4のIDのnetworkを開き、Add Resourceで次のNetwork Resourceを追加する。
   このnetworkの名前は`cffnpwr-home`であり、RoutersにはOperatorの作成したルーティングピアがある

   | 項目 | 値 |
   | --- | --- |
   | Name | `cffnpwr-home-lan` |
   | Address | `192.168.0.0/23` |
   | Groups | `cffnpwr-home-lan` |

   ダッシュボードではnetworkを新しく作成しない。
   ルーティングピアのないnetworkにNetwork Resourceを追加すると、CIのピアは自宅LANに接続できない。
   Access Control Policyは手順8で`terraform/netbird/`が作成するため、ダッシュボードでは作成しない。
   v1alpha1の`NetworkResource`はCIDRを宛先に指定できないため、このNetwork Resourceはダッシュボードで管理する。
6. ダッシュボードでCIのplan・applyが使う2つのサービスユーザーとそれぞれのPATを作成する。
   plan用のサービスユーザーには読み取り専用のロールを、apply用のサービスユーザーには管理者のロールを設定する
7. 手順6のPATを`TF_VAR_netbird_pat_read_only`・`TF_VAR_netbird_pat_read_write`に設定し、[bootstrapの再実行](./terraform.md#bootstrapの再実行)の手順で`NB_PAT`に登録する。
   bootstrapの構築時にはPATがまだないため、`NB_PAT`には空文字列が登録されている
8. apply用のPATを`NB_PAT`環境変数に設定し、`terraform/netbird/`をapplyする。
   このapplyでCIのグループ・ephemeralのsetup key・CIから`cffnpwr-home-lan`グループへのポリシーを作成する。
   setup keyは`terraform-plan`・`terraform-apply`・`sealed-secrets-reseal`のenvironmentに`NETBIRD_SETUP_KEY`として登録される

   ```sh
   mise run tf:netbird init
   mise run tf:netbird apply
   ```

クラスタを再構築した後は、手順4・5でNetwork Resourceを追加し直す。
`NetworkRouter`のstatusにnetworkのIDがない場合、Operatorはnetworkを新しく作成するため、以前のNetwork Resourceは引き継がれない。
