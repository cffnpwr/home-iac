# クラスタの初回構築

この手順書はクラスタを初めて構築するときの手順を説明する。
次の順に実行する。

1. bootstrapの構築
2. GitHub Appの作成
3. クラスタの構築
4. ローカルサーバーの参加
5. netbirdの設定

## Prerequisites

- `mise install`でツールをインストール済み
- [bootstrap用のトークン](./terraform.md#bootstrap用のトークン)を作成済み
- `terraform-apply`が使う、読み書きできるCloudflareのAPIトークンをダッシュボードで作成済み
  - CIのapplyはこのトークンからS3 backendの認証情報を作る
  - このためトークンには`home-iac-tfstate`のR2 Bucketを読み書きする権限も付ける
- Google WorkspaceのAccess用のOAuthクライアントをGoogle Cloudのコンソールで作成済み

Terraformは作成するトークンの名前に`[managed by terraform] home-iac/`を付ける。
ダッシュボードで作成するトークンの名前には`[managed by terraform] `を付けない。

## bootstrapの構築

`terraform/bootstrap/`はtfstate用のR2 Bucketと、CIのjobが使う認証情報を作成する。
bootstrapのstateを置くBucketもbootstrapが作成するため初回はローカルのstateを作成してから移行する。

1. SSE-Cの鍵を生成しageで暗号化して`terraform/bootstrap/sse-customer-key.age`に書く。
   宛先は`kubernetes/apps/sealed-secrets-backup/recipients.yaml`の`recipients.txt`である。
   生成した`sse-customer-key.age`はコミットする。

   ```sh
   mise run tf:bootstrap:generate-sse-customer-key
   ```

2. [`terraform/bootstrap/`の環境変数](./terraform.md#terraformbootstrapの環境変数)を設定する。
   netbirdのPATはクラスタの構築後に作成するため、`TF_VAR_netbird_pat_read_only`・`TF_VAR_netbird_pat_read_write`には空文字列を設定する。
3. `terraform/bootstrap/backend_override.tf`に次の内容を記載する。

   ```hcl
   terraform {
     backend "local" {}
   }
   ```

4. bootstrapをapplyする。

   ```sh
   mise run tf:bootstrap init
   mise run tf:bootstrap plan
   mise run tf:bootstrap apply
   ```

5. `terraform/bootstrap/backend_override.tf`を削除する。
6. stateをR2 Bucketへ移行しローカルのstateを削除する。

   ```sh
   mise run tf:bootstrap init -migrate-state
   rm -f terraform/bootstrap/terraform.tfstate terraform/bootstrap/terraform.tfstate.backup
   ```

7. Vultrのコンソールで、bootstrapが作成したservice userのAPIキーをすべてのIPアドレスから使えるようにする。
   VultrはAPIキーを使えるIPアドレスをユーザーごとに制限し、Terraformのproviderはこの設定を管理できない。
   GitHub-hostedのrunnerのIPアドレスは実行のたびに変わるため、すべてのIPアドレスを許可する。
   次の操作を`terraform-plan`・`terraform-apply`のservice userごとに行なう。
   1. 上部のナビゲーションバーで組織の名前を選び、Manage Organizationを開く。
   2. Usersで対象のservice userを選ぶ。
   3. API AccessのAccess Control Listで、Any IPv4・Any IPv6を有効にする。

## GitHub Appの作成

CIのjobと鍵の退避Jobが使う4つのGitHub Appをmanifest flowで作成する。
GitHub Appの種類と権限は[CIでのplan・apply](./terraform.md#ciでのplanapply)にある。
次の手順は`plan`・`apply`・`reseal`・`backup`の種類ごとに実行する。

1. タスクを実行する。
   タスクはGitHub Appの登録の画面のURLを表示しブラウザで開く。
   ブラウザが開かない場合は表示したURLをブラウザで開く。
   `backup`では`--cert`にbootstrapのoutputの`sealed_secrets_cert`を書いたファイルを指定する。
   `--cert`の相対パスはリポジトリのルートを基準にする。

   ```sh
   mise run github:create-app <種類>
   ```

2. ブラウザでGitHub Appの名前を確認してCreate GitHub Appを選ぶ。
3. タスクが表示するインストールの画面で`home-iac`だけにインストールする。
   タスクはインストールを確認した後にClient IDと秘密鍵をenvironmentに登録する。
   `backup`では`kubernetes/apps/sealed-secrets-backup/sealed-secrets-backup-github-app.yaml`にSealedSecretを書く。

タスクはslug・App ID・Client IDだけを出力し秘密鍵は出力しない。
登録済みのClient IDを置き換える場合は`--force`を指定する。

### 非GUI環境での実行

GitHubはGitHub Appを登録した後にブラウザを`http://127.0.0.1:<ポート>/callback`へリダイレクトする。
このURLはタスクを実行するホストで待ち受けている。
SSHで接続したホストでタスクを実行する場合は、手元のブラウザからホストのポートに接続できるようにポートを転送する。

1. ポートを転送してホストに接続する。

   ```sh
   ssh -L 8080:127.0.0.1:8080 <ホスト>
   ```

2. 転送したポートを`--listen-port`に指定してタスクを実行する。

   ```sh
   mise run github:create-app <種類> --listen-port 8080
   ```

3. タスクが表示したURLを手元のブラウザで開き、[GitHub Appの作成](#github-appの作成)の手順2から続ける。

## クラスタの構築

mainのrootの初回のapplyは手元で実行する。
CIのjobはクラスタの上で動作するnetbirdを経由してクラスタに接続するため、クラスタの構築前には接続できない。
[`terraform/`の環境変数](./terraform.md#terraformの環境変数)を設定してから次の手順を実行する。
`CLOUDFLARE_API_TOKEN`は`terraform-apply`のトークンに置き換える。
bootstrap用のトークンは`BOOTSTRAP_CLOUDFLARE_API_TOKEN`に設定する。

1. RPi4用のイメージのURLを確定させる。
   URLはImage Factoryに登録したschematicのIDから決まるため、schematicだけを先に作成し、表示される`urls.disk_image`を参照する。

   ```sh
   mise run tf apply -target=module.rpi4.data.talos_image_factory_urls.this
   mise run tf state show module.rpi4.data.talos_image_factory_urls.this
   ```

2. イメージをダウンロード・展開し、SDカードへ書き込む。

   ```sh
   curl -LO <手順1で得たURL>
   xz -d metal-arm64.raw.xz
   sudo dd if=metal-arm64.raw of=<SDカードのデバイス> conv=fsync bs=4M
   ```

3. SDカードをRPi4に挿して起動する。
   RPi4はschematicのカーネル引数に設定した静的IPアドレスで起動し、machine configの適用を待つ。
4. `terraform apply`でRPi4へmachine configを適用してクラスタをbootstrapし、Vultr上にworkerを作成する。

   ```sh
   mise run tf apply
   ```

5. talosconfigを取得する。

   ```sh
   mise run tf output -raw talosconfig > talosconfig
   ```

## ローカルサーバーの参加

ローカルサーバー（`terraform/main.tf`の`local.servers`）のcontrol planeは、ISOから手作業で起動して参加させる。
次の手順は、サーバーごとに実行する。

1. サーバー用のISOのURLを確定させる。
   `<ホスト名>`は`local.servers`のキー（例: `cpwr-svr1`）である。

   ```sh
   mise run tf apply -target='module.servers["<ホスト名>"].data.talos_image_factory_urls.this'
   mise run tf output -json server_iso_urls
   ```

2. ISOをダウンロードし、USBメモリへ書き込む。

   ```sh
   curl -LO <手順1で得たURL>
   sudo dd if=metal-amd64-secureboot.iso of=<USBメモリのデバイス> conv=fsync bs=4M
   ```

3. サーバーのUEFIの設定でSecure Bootを有効にし、Setup Modeにする。
4. サーバーのブートメニューでUSBメモリを選び、ISOから起動する。
   初回の起動では、ISOのブートメニュー（Escで表示）で`Enroll Secure Boot keys: auto`を選び、Secure Bootの鍵を登録する。
   サーバーはschematicのカーネル引数に設定した静的IPアドレスで起動し、machine configの適用を待つ。
5. `terraform apply`でサーバーへmachine configを適用する。
   TalosはNVMeのディスクにインストールされ、再起動後にクラスタへ参加する。
   インストール後の再起動で再びISOから起動した場合は、USBメモリを取り外して再起動する。

   ```sh
   mise run tf apply
   ```

## netbirdの設定

CIのjobはnetbirdのルーティングピアを経由して自宅LANのクラスタに接続する。
ルーティングピアはArgo CDが同期する`NetworkRouter`からnetbird Operatorが作成する。
クラスタの構築後に、次の手順でルーティングピアとCIの接続を設定する。

1. netbirdのダッシュボードで、Operator用のサービスユーザーとそのPATを作成する。
2. PATを`netbird`のnamespaceの`netbird-mgmt-api-key`というSecretの`NB_API_KEY`として、[kubesealでのSealedSecretの作成](./sealed-secrets.md)の手順で`kubernetes/apps/netbird/netbird-mgmt-api-key.yaml`に封入する。
3. ダッシュボードで、名前とドメインがどちらも`cffnpwr-home.internal`のDNSゾーンを作成する。
   Operatorは`NetworkRouter`の`dnsZoneRef`をDNSゾーンの名前で検索する。
4. Argo CDが`NetworkRouter`を同期した後に、Operatorが作成したnetworkのIDを確認する。

   ```sh
   kubectl get networkrouter -n netbird cffnpwr-home -o jsonpath='{.status.networkID}'
   ```

5. ダッシュボードのNetworksで、手順4のIDのnetworkを開き、Add Resourceで次のNetwork Resourceを追加する。
   このnetworkの名前は`cffnpwr-home`で、Operatorが作成したルーティングピアがRoutersにある。

   | 項目 | 値 |
   | --- | --- |
   | Name | `cffnpwr-home-lan` |
   | Address | `192.168.0.0/23` |
   | Groups | `cffnpwr-home-lan` |

   ダッシュボードではnetworkを新しく作成しない。
   ルーティングピアの無いnetworkにNetwork Resourceを追加すると、CIのピアは自宅LANに接続できない。
   Access Control Policyは手順8で`terraform/netbird/`が作成するため、ダッシュボードでは作成しない。
   v1alpha1の`NetworkResource`はCIDRを宛先に指定できないため、このNetwork Resourceはダッシュボードで管理する。
6. ダッシュボードで、CIのplan・applyが使う2つのサービスユーザーとそれぞれのPATを作成する。
   planのサービスユーザーには読み取りだけを許可したロールを、applyのサービスユーザーには管理者のロールを設定する。
7. 手順6のPATを`TF_VAR_netbird_pat_read_only`・`TF_VAR_netbird_pat_read_write`に設定し、[bootstrapの再実行](./terraform.md#bootstrapの再実行)の手順で`NB_PAT`に登録する。
   bootstrapの構築ではPATがまだ無いため、`NB_PAT`には空文字列が登録されている。
8. applyのPATを`NB_PAT`環境変数に設定して、`terraform/netbird/`をapplyする。
   CIのグループ・ephemeralのsetup key・CIから`cffnpwr-home-lan`グループへのポリシーを作成する。
   setup keyは、`terraform/bootstrap/`が作成した`terraform-plan`・`terraform-apply`・`sealed-secrets-reseal`のenvironmentに`NETBIRD_SETUP_KEY`として登録する。

   ```sh
   mise run tf:netbird init
   mise run tf:netbird apply
   ```

クラスタを再構築した後は、手順4・5でNetwork Resourceを追加し直す。
`NetworkRouter`のstatusにnetworkのIDが無い場合、Operatorはnetworkを新しく作成するため、以前のnetworkのNetwork Resourceは引き継がれない。
