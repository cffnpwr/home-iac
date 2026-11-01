# クラスタの初回構築

この手順書はクラスタを初めて構築するときの手順を説明する。
次の順に実行する。

1. tfstate用のR2 Bucketの作成
2. クラスタの構築
3. ローカルサーバーの参加
4. netbirdの設定

## Prerequisites

- `mise install`でツールをインストール済み
- GitHub Appに[CIでのapply](./terraform.md#ciでのapply)の権限を付与済み
- [Terraformのplan・apply](./terraform.md#prerequisites)の環境変数を設定済み
- CIのシークレットに登録するため、`TF_VAR_cloudflare_api_token_read_only`・`TF_VAR_cloudflare_api_token_read_write`・`TF_VAR_vultr_api_key`を設定済み（[CIのシークレットの更新](./terraform.md#ciのシークレットの更新)）

## tfstate用のR2 Bucketの作成

tfstate管理用のR2 Bucketが未作成の場合は作成する。

tfstate用のR2 Bucketは同じTerraformで管理する。
Bucketができるまでリモートのstateは使えないため、初回はローカルのstateを作成してから移行する。

1. `terraform/backend_override.tf`に次の内容を記載する。

   ```hcl
   terraform {
     backend "local" {}
   }
   ```

2. Bucketを作成する。

   ```sh
   mise run tf init
   mise run tf plan
   mise run tf apply
   ```

3. `terraform/backend_override.tf`を削除する。
4. tfstateをR2 Bucketへ移行する。

   ```sh
   mise run tf init -migrate-state
   ```

## クラスタの構築

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

ローカルサーバー（`terraform/main.tf`の`local.servers`）のworkerは、ISOから手作業で起動して参加させる。
次の手順は、サーバーごとに実行する。

1. サーバー用のISOのURLを確定させる。
   `<ホスト名>`は`local.servers`のキー（例: `cpwr-srvr`）である。

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
7. [CIのシークレットの更新](./terraform.md#ciのシークレットの更新)の手順で、手順6のPATを`NB_PAT`に登録する。
   クラスタの構築時の`terraform/`のapplyでは、PATがまだ無いため、`NB_PAT`には空文字列が登録されている。
8. applyのPATを`NB_PAT`環境変数に設定して、`terraform/netbird/`をapplyする。
   CIのグループ・ephemeralのsetup key・CIから`cffnpwr-home-lan`グループへのポリシーを作成する。
   setup keyは、`terraform/`が作成した`terraform-plan`・`terraform-apply`・`sealed-secrets-reseal`のenvironmentに`NETBIRD_SETUP_KEY`として登録する。

   ```sh
   mise run tf:netbird init
   mise run tf:netbird apply
   ```

クラスタを再構築した後は、手順4・5でNetwork Resourceを追加し直す。
`NetworkRouter`のstatusにnetworkのIDが無い場合、Operatorはnetworkを新しく作成するため、以前のnetworkのNetwork Resourceは引き継がれない。
