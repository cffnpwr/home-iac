# Terraformのplan・apply

この手順書はTerraformのplan・applyと、CIが使う認証情報の更新の手順を説明する。

- Terraformのroot
- CIでのplan・apply
- 手元からのapply
- bootstrapの再実行

## Prerequisites

- `mise install`でツールをインストール済み

## Terraformのroot

Terraformのrootは3つある。
PRのplan jobに渡る認証情報を減らすため、CIの認証情報とクラスタの鍵を作るrootをCIのrootから分けている。

| root | 実行する場所 | 管理するリソース |
| --- | --- | --- |
| `terraform/bootstrap/` | 手元 | tfstate用のR2 Bucket・Talosのmachine secrets・Sealed Secretsの初期の鍵とHMACの鍵・Google WorkspaceのAccessのidentity provider・GitHubのenvironmentとCIの認証情報 |
| `terraform/` | CI（初回は手元） | 各ノードのmachine config・`talos_cluster`・inline manifest・アプリ用のCloudflareのリソース・Pocket IDのidentity provider・`sealed_secrets`のoutput |
| `terraform/netbird/` | CI | CIのnetbirdのグループ・setup key・ポリシー |

`terraform/bootstrap/`のstateは`terraform/`・`terraform/netbird/`と同じR2 Bucket（`home-iac-tfstate`）に保存する。
bootstrapのstateはSSE-Cで暗号化する。
CIのjobはこのBucketを読めるがSSE-Cの鍵を渡さないため、bootstrapのstateは取得できない。
`terraform/`はbootstrapが生成した値をenvironmentのシークレット・variableから変数で受け取る。

### `terraform/bootstrap/`の環境変数

`mise run tf:bootstrap`は`terraform/bootstrap/scripts/cmd/tf`を経由して`terraform`を実行する。
`cmd/tf`は`CLOUDFLARE_API_TOKEN`のトークンからS3 backendの認証情報を作る。
`AWS_SSE_CUSTOMER_KEY`が未設定の場合`cmd/tf`は`sse-customer-key.age`を復号してSSE-Cの鍵にする。
復号には`AGE_IDENTITY_FILE`のidentityを使う。
`AGE_IDENTITY_FILE`の相対パスはリポジトリのルートを基準にする。
タスクは`go run`で`cmd/tf`を実行するため、`terraform`が0以外の終了ステータスで終了するとタスクは終了ステータス1で終了する。

| 環境変数 | 内容 |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | bootstrap用のCloudflareのアカウントのAPIトークン（[bootstrap用のトークン](#bootstrap用のトークン)） |
| `VULTR_API_KEY` | VultrのアカウントのAPIキー |
| `AGE_IDENTITY_FILE` | `sse-customer-key.age`を復号するageのidentityファイルのパス（`AWS_SSE_CUSTOMER_KEY`を設定する場合は不要） |
| `TF_VAR_cloudflare_api_token_apply` | `terraform-apply`の`CLOUDFLARE_API_TOKEN`に登録する読み書きできるAPIトークン |
| `TF_VAR_netbird_pat_read_only` | `terraform-plan`の`NB_PAT`に登録する、読み取り専用のサービスユーザーのPAT |
| `TF_VAR_netbird_pat_read_write` | `terraform-apply`の`NB_PAT`に登録する、管理者のサービスユーザーのPAT |
| `TF_VAR_google_workspace_access_client_secret` | AccessがGoogle Workspaceにログインするときに使う、OAuthクライアントのシークレット |

GitHub providerは`GITHUB_TOKEN`環境変数のトークンを使い未設定なら`gh auth token`のトークンを使う。

#### ageのidentityファイル

`AWS_SSE_CUSTOMER_KEY`が未設定の場合、`terraform/bootstrap/scripts/cmd/tf`は`sse-customer-key.age`からSSE-Cの鍵を復号する。
`sse-customer-key.age`は`terraform/bootstrap/`にある。
`sse-customer-key.age`は`kubernetes/apps/sealed-secrets-backup/recipients.yaml`の宛先で暗号化されている。
宛先は、`recipients.yaml`のConfigMapの`data["recipients.txt"]`に1行ずつ書いてある。
Sealed Secretsの鍵の退避Job（`kubernetes/apps/sealed-secrets-backup/backup.sh`）も、同じ宛先で鍵を暗号化する。
宛先は次の2つで、どちらか1つのidentityがあれば復号できる。

| 宛先の接頭辞 | 鍵の場所 | 手順 |
| --- | --- | --- |
| `age1yubikey1` | YubiKeyのPIVの鍵 | [YubiKeyを使う場合](#yubikeyを使う場合) |
| `age1tag1` | 鍵を作成したMacのSecure Enclave | [Secure Enclaveを使う場合](#secure-enclaveを使う場合) |

宛先の値は、リポジトリのルートで次のコマンドを実行して表示する。

```sh
yq '.data["recipients.txt"]' kubernetes/apps/sealed-secrets-backup/recipients.yaml
```

identityファイルは、YubiKey・Secure Enclaveにある鍵を参照する情報を書いたテキストファイルである。
identityファイルだけでは復号できず、復号には参照先の鍵が必要である。
このため、YubiKeyを使う場合は鍵のあるYubiKeyを接続し、Secure Enclaveを使う場合は鍵を作成したMacで実行する。

`AGE_IDENTITY_FILE`は、`mise run tf:bootstrap`を実行するシェルで`export`して設定する。
次の手順では、identityファイルの絶対パスを設定する。

##### YubiKeyを使う場合

1. YubiKeyをMacに接続する。
2. 次のコマンドでidentityファイルを`$HOME/yubikey-identity.txt`に作成する。
   同じ名前のファイルがある場合は上書きされる。

   ```sh
   age-plugin-yubikey --identity > "$HOME/yubikey-identity.txt"
   ```

3. 次のコマンドでidentityファイルを表示する。

   ```sh
   cat "$HOME/yubikey-identity.txt"
   ```

   identityファイルには、YubiKeyのidentityごとに次の形式の組が並ぶ。

   ```text
   #       Serial: <シリアル番号>, Slot: <スロット>
   #         Name: <名前>
   #      Created: <作成日時>
   #   PIN policy: <PINのポリシー>
   # Touch policy: <タッチのポリシー>
   #    Recipient: <宛先>
   AGE-PLUGIN-YUBIKEY-...
   ```

4. `Recipient:`の値が`recipients.txt`の`age1yubikey1`で始まる宛先と一致する組を探す。
   一致する組が見つからない場合は、接続したYubiKeyでは復号できない。
   別のYubiKeyを接続して手順2からやり直すか、[Secure Enclaveを使う場合](#secure-enclaveを使う場合)の手順を使う。
5. 一致した組の`PIN policy:`・`Touch policy:`の値を確認する。
   この2つの値で、復号の操作でPINの入力とタッチが必要かが決まる。
6. `AGE_IDENTITY_FILE`を設定する。

   ```sh
   export AGE_IDENTITY_FILE="$HOME/yubikey-identity.txt"
   ```

リポジトリのディレクトリで`mise run tf:bootstrap`を実行すると、`cmd/tf`は`terraform`を実行する前に`sse-customer-key.age`を復号する。
復号では、`PIN policy:`・`Touch policy:`の値に応じて次の操作を行なう。

| 値 | 操作 |
| --- | --- |
| `PIN policy:`が`Always`・`Once` | `Enter PIN for YubiKey with serial <シリアル番号>`が表示されたら、YubiKeyのPIV PINを入力する。FIDO2のPINではない |
| `PIN policy:`が`Never` | PINの入力は求められない |
| `Touch policy:`が`Always`・`Cached` | YubiKeyが点滅したら、点滅している間にYubiKeyへ触れる。タッチを求めるメッセージは端末に表示されない。PINを入力する場合は、PINの入力の後に点滅する |
| `Touch policy:`が`Never` | タッチは求められない |

YubiKeyに触れないまま時間が経過すると、YubiKeyがタイムアウトして復号は失敗する。
復号に失敗すると、`cmd/tf`はエラーを表示して終了し、`terraform`を実行しない。
復号に成功すると、`terraform`の出力が表示される。

YubiKeyのPIV PINの初期値は`123456`、PUKの初期値は`12345678`である。
PIV PINを3回続けて間違えると、PIV PINがロックされる。
ロックはPUKとYubiKey Manager（`ykman`）で解除する。
`ykman`は`mise install`ではインストールされないため、[YubiKey Managerのドキュメント](https://docs.yubico.com/software/yubikey/tools/ykman/)に従ってインストールする。

```sh
ykman piv access unblock-pin --puk <PUK> --new-pin <新しいPIV PIN>
```

PUKも3回続けて間違えると、PUKがロックされてPIV PINのロックを解除できなくなる。

##### Secure Enclaveを使う場合

1. 鍵を作成したMacで、`age-plugin-se keygen -o <ファイル>`で鍵を作成したときの`<ファイル>`を探す。
   このファイルがidentityファイルである。
   パスが分からない場合は、次のコマンドでホームディレクトリから探す。

   ```sh
   grep -rls 'AGE-PLUGIN-SE-1' "$HOME"
   ```

   ファイルが見つからない場合は、このMacでは復号できない。
   [YubiKeyを使う場合](#yubikeyを使う場合)の手順を使う。
2. 次のコマンドでidentityファイルの宛先を表示する。

   ```sh
   age-plugin-se recipients --recipient-type tag -i <identityファイルのパス>
   ```

3. 表示された宛先が、`recipients.txt`の`age1tag1`で始まる宛先と一致することを確認する。
   一致しない場合は、このidentityファイルでは復号できない。
   [YubiKeyを使う場合](#yubikeyを使う場合)の手順を使う。
4. `AGE_IDENTITY_FILE`を設定する。

   ```sh
   export AGE_IDENTITY_FILE=<identityファイルの絶対パス>
   ```

リポジトリのディレクトリで`mise run tf:bootstrap`を実行すると、macOSが認証の画面を表示する。
画面の指示に従い、Touch IDかMacのパスワードで認証する。
使える認証の方法は、`age-plugin-se keygen`で`--access-control`に指定した値で決まる。
identityファイルの`# access control:`の行に、その値が書いてある。
復号に成功すると、`terraform`の出力が表示される。

#### bootstrap用のトークン

bootstrap用のトークンはCloudflareのダッシュボードでアカウントのトークン（Account API Tokens）として作成する。
`cmd/tf`はアカウントのトークンの検証APIでトークンのIDを取得するためユーザーのトークンは使えない。
`terraform/bootstrap/`が管理するリソースに合わせて次の権限を付ける。

| 権限 | 使うリソース |
| --- | --- |
| Account API Tokens Write | CI用のトークンの作成・権限グループの取得 |
| Workers R2 Storage Write | tfstate用のR2 Bucket・bootstrapのstate |
| Access: Organizations, Identity Providers, and Groups Write | Google Workspaceのidentity provider |
| Zone Read | `cffnpwr.dev`のゾーンの取得 |

### `terraform/`の環境変数

`terraform/`を手元で実行する前に次の環境変数を設定する。

| 環境変数 | 内容 |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | R2 APIトークンのアクセスキーID（S3バックエンド用） |
| `AWS_SECRET_ACCESS_KEY` | R2 APIトークンのシークレットアクセスキー（S3バックエンド用） |
| `CLOUDFLARE_API_TOKEN` | Cloudflare provider用のAPIトークン |
| `VULTR_API_KEY` | Vultr provider用のAPIキー |
| `TF_VAR_pocket_id_access_client_secret` | AccessがPocket IDにログインするときに使う、OIDCクライアントのシークレット |
| `TF_VAR_talos_machine_secrets` | bootstrapのoutputの`talos_machine_secrets` |
| `TF_VAR_sealed_secrets_private_key` | bootstrapのoutputの`sealed_secrets_private_key` |
| `TF_VAR_sealed_secrets_cert` | bootstrapのoutputの`sealed_secrets_cert` |
| `TF_VAR_google_workspace_access_identity_provider_id` | bootstrapのoutputの`google_workspace_access_identity_provider_id` |

bootstrapのoutputの値は次のように設定する。
objectのoutputは`-json`で取り出し文字列のoutputは`-raw`で取り出す。
`BOOTSTRAP_CLOUDFLARE_API_TOKEN`はbootstrap用のトークンである。
`terraform/`の`CLOUDFLARE_API_TOKEN`とbootstrap用のトークンは異なるため、bootstrapの実行時だけ`CLOUDFLARE_API_TOKEN`を置き換える。

```sh
bootstrap_output() {
  CLOUDFLARE_API_TOKEN="$BOOTSTRAP_CLOUDFLARE_API_TOKEN" mise run tf:bootstrap output "$@"
}
export TF_VAR_talos_machine_secrets="$(bootstrap_output -json talos_machine_secrets)"
export TF_VAR_sealed_secrets_private_key="$(bootstrap_output -raw sealed_secrets_private_key)"
export TF_VAR_sealed_secrets_cert="$(bootstrap_output -raw sealed_secrets_cert)"
export TF_VAR_google_workspace_access_identity_provider_id="$(bootstrap_output -raw google_workspace_access_identity_provider_id)"
```

netbirdのリソースを管理する`terraform/netbird/`では、次の環境変数も設定する。

| 環境変数 | 内容 |
| --- | --- |
| `NB_PAT` | netbird provider用の、管理者のサービスユーザーのPAT |

## CIでのplan・apply

PRでは`.github/workflows/terraform-plan.yaml`のworkflowが`terraform/`・`terraform/netbird/`をplanする。
mainへのマージでは、`.github/workflows/terraform-apply.yaml`のworkflowが`terraform/`・`terraform/netbird/`の順にapplyする。
applyの後に、SealedSecretを再暗号化するworkflowを実行する。
`terraform/bootstrap/`だけを変更した場合どちらのworkflowも実行されない。

CIのjobと鍵の退避Jobは次の4種類のGitHub Appのトークンを使う。
GitHub Appは`mise run github:create-app <種類>`でmanifest flowから作成する（[クラスタの初回構築](./initial-setup.md#github-appの作成)）。
TerraformではGitHub Appの作成とインストールを管理できない。

| 種類 | GitHub App | Repository permissions | Client IDと秘密鍵の登録先 |
| --- | --- | --- | --- |
| `plan` | `cffnpwr-home-iac-plan` | Metadata: Read-only・Environments: Read-only | `terraform-plan`の`PLAN_APP_CLIENT_ID`・`PLAN_APP_PRIVATE_KEY` |
| `apply` | `cffnpwr-home-iac-apply` | Metadata: Read-only・Environments: Read and write | `terraform-apply`の`APPLY_APP_CLIENT_ID`・`APPLY_APP_PRIVATE_KEY` |
| `reseal` | `cffnpwr-home-iac-reseal` | Contents: Read and write・Pull requests: Read and write | `sealed-secrets-reseal`の`RESEAL_APP_CLIENT_ID`・`RESEAL_APP_PRIVATE_KEY` |
| `backup` | `cffnpwr-home-iac-key-backup` | Contents: Read and write | `kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml`のSealedSecret |

### Talos APIのクライアント証明書の更新

`terraform/`はTalos APIへ接続するクライアント証明書をmachine secretsのCAで発行する。
証明書の有効期間は1年で、期限の30日前からapplyで更新される。
`terraform-apply.yaml`は毎週1回scheduleでapplyを実行するため証明書は期限の前に更新される。

証明書を更新するとtalosconfigが変わる。
Vultrのインスタンスの置換と同じapplyで証明書を更新すると、applyはエラーで終了する。
古いインスタンスを削除する`terminate_node`のactionの設定が、apply中に確定しないためである。
Vultrのインスタンスを置換する変更はPRのplanに`tls_locally_signed_cert.talos_client`の置換が無いことを確認してからマージする。
置換が含まれる場合は先にmainで`terraform-apply.yaml`をworkflow_dispatchで実行して証明書を更新し、PRのplanを再実行して確認する。

## 手元からのapply

CIからクラスタへ接続できない場合と、CIの接続に使うnetbirdのポリシー・setup keyを変更する場合は、手元の端末から次の手順でapplyする。
`terraform/netbird/`では`mise run tf`の代わりに`mise run tf:netbird`を使う。

1. `terraform plan`で変更内容を確認する。

   ```sh
   mise run tf plan
   ```

2. `terraform apply`で変更を適用する。

   ```sh
   mise run tf apply
   ```

## bootstrapの再実行

`terraform/bootstrap/`は次の値を更新する場合に手元からapplyする。

- CIの認証情報（netbirdのPAT・`terraform-apply`のCloudflareのAPIトークン・Vultrのservice userのAPIキー）
- Google WorkspaceのOAuthクライアントのシークレット
- bootstrap用のCloudflareのAPIトークン

CIの認証情報とGoogle Workspaceのシークレットは新しい値を[`terraform/bootstrap/`の環境変数](#terraformbootstrapの環境変数)に設定してapplyする。
bootstrapのすべての変数は必須で変数の値の変更はplanの差分になる。

```sh
mise run tf:bootstrap plan
mise run tf:bootstrap apply
```

Vultrのservice userのAPIキーを作り直す場合は対象のservice userに`-replace`を指定してapplyする。

```sh
mise run tf:bootstrap apply -replace='vultr_user.terraform["plan"]'
```

`-replace`はservice userを作り直すため、作り直したservice userはどのIPアドレスからもAPIキーを使えない。
applyの後に[クラスタの初回構築](./initial-setup.md#bootstrapの構築)の手順7で、Any IPv4・Any IPv6を有効にする。

bootstrap用のCloudflareのAPIトークンを更新する場合はダッシュボードで新しいトークンを作成する。
新しいトークンを`CLOUDFLARE_API_TOKEN`に設定し`plan`で差分が無いことを確認する。
S3 backendの認証情報はトークンから作るため、新しいトークンにもbootstrapのstateのR2 Bucketを読み書きする権限が必要である。
確認した後に古いトークンをダッシュボードで削除する。

Google WorkspaceのOAuthクライアントのシークレットを更新した後もidentity providerのIDは変わらない。
identity providerを作り直した場合はbootstrapがvariable`GOOGLE_WORKSPACE_ACCESS_IDENTITY_PROVIDER_ID`を更新する。
新しいIDをAccessのアプリとポリシーに反映するため`terraform/`をapplyする。
