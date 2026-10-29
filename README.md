# Home IaC

[![GitHub License](https://img.shields.io/github/license/cffnpwr/home-iac?style=flat)](./LICENSE)

cffnpwrの自宅クラスタを管理するIaCリポジトリです。

## Requirements

- [mise](https://mise.jdx.dev/)が使用可能

## How to setup

1. このリポジトリをクローンします。

   ```sh
   git clone https://github.com/cffnpwr/home-iac.git
   cd home-iac
   ```

2. `mise install`でツールをインストールします。

   ```sh
   mise install
   ```

## How to deploy

### Prerequisites

Terraformを実行する前に以下の環境変数を設定しておく必要があります。

| 環境変数 | 内容 |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | R2 APIトークンのアクセスキーID（S3バックエンド用） |
| `AWS_SECRET_ACCESS_KEY` | R2 APIトークンのシークレットアクセスキー（S3バックエンド用） |
| `CLOUDFLARE_API_TOKEN` | Cloudflare provider用のAPIトークン |
| `VULTR_API_KEY` | Vultr provider用のAPIキー |
| `TF_VAR_github_app_client_id` | 鍵の退避Jobがrepository_dispatchを送信するときに使うGitHub AppのClient ID |
| `TF_VAR_github_app_private_key` | 鍵の退避Jobがrepository_dispatchを送信するときに使うGitHub Appの秘密鍵（PEM） |

GitHub providerは`GITHUB_TOKEN`環境変数のトークンを使い、未設定なら`gh auth token`のトークンを使います。

### Initial setup

tfstate管理用のR2 Bucketが未作成の場合は作成しておく必要があります。

tfstate用のR2 Bucketは同じTerraformで管理されます。
Bucketができるまでリモートのstateは使えないため、初回はローカルのstateを作成してから移行します。

1. `terraform/backend_override.tf`に次の内容を記載します。

   ```hcl
   terraform {
     backend "local" {}
   }
   ```

2. Bucketを作成します。

   ```sh
   mise run tf init
   mise run tf plan
   mise run tf apply
   ```

3. `terraform/backend_override.tf`を削除します。
4. tfstateをR2 Bucketへ移行します。

   ```sh
   mise run tf init -migrate-state
   ```

### Cluster setup

クラスタの初回構築は次の手順で行います。

1. RPi4用のイメージのURLを確定させます。
   URLはImage Factoryに登録したschematicのIDから決まるため、schematicだけを先に作成し、表示される`urls.disk_image`を参照します。

   ```sh
   mise run tf apply -target=module.rpi4.data.talos_image_factory_urls.this
   mise run tf state show module.rpi4.data.talos_image_factory_urls.this
   ```

2. イメージをダウンロード・展開し、SDカードへ書き込みます。

   ```sh
   curl -LO <手順1で得たURL>
   xz -d metal-arm64.raw.xz
   sudo dd if=metal-arm64.raw of=<SDカードのデバイス> conv=fsync bs=4M
   ```

3. SDカードをRPi4に挿して起動します。
   RPi4はschematicのカーネル引数に設定した静的IPアドレスで起動し、machine configの適用を待ちます。
4. `terraform apply`でRPi4へmachine configを適用してクラスタをbootstrapし、Vultr上にworkerを作成します。

   ```sh
   mise run tf apply
   ```

5. talosconfigを取得します。

   ```sh
   mise run tf output -raw talosconfig > talosconfig
   ```

### Local server setup

ローカルサーバー（`cpwr-srvr`）のworkerは、ISOから手作業で起動して参加させます。

1. サーバー用のISOのURLを確定させます。

   ```sh
   mise run tf apply -target=module.server.data.talos_image_factory_urls.this
   mise run tf output -raw server_iso_url
   ```

2. ISOをダウンロードし、USBメモリへ書き込みます。

   ```sh
   curl -LO <手順1で得たURL>
   sudo dd if=metal-amd64-secureboot.iso of=<USBメモリのデバイス> conv=fsync bs=4M
   ```

3. サーバーのUEFIの設定でSecure Bootを有効にし、Setup Modeにします。
4. サーバーのブートメニューでUSBメモリを選び、ISOから起動します。
   初回の起動では、ISOのブートメニュー（Escで表示）で`Enroll Secure Boot keys: auto`を選び、Secure Bootの鍵を登録します。
   サーバーはschematicのカーネル引数に設定した静的IPアドレスで起動し、machine configの適用を待ちます。
5. `terraform apply`でサーバーへmachine configを適用します。
   TalosはNVMeのディスクにインストールされ、再起動後にクラスタへ参加します。
   インストール後の再起動で再びISOから起動した場合は、USBメモリを取り外して再起動します。

   ```sh
   mise run tf apply
   ```

### Plan & Apply

1. `terraform plan`で変更内容を確認します。

   ```sh
   mise run tf plan
   ```

2. `terraform apply`で変更を適用します。

   ```sh
   mise run tf apply
   ```

## License

[MIT License](./LICENSE)
