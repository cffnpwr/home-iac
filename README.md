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
