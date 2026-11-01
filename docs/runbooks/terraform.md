# Terraformのplan・apply

この手順書はTerraformのplan・applyと、CIが使うシークレットの更新の手順を説明する。

- CIでのapply
- 手元からのapply
- CIのシークレットの更新

## Prerequisites

- `mise install`でツールをインストール済み

`terraform/`を実行する前に、次の環境変数を設定する。

| 環境変数 | 内容 |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | R2 APIトークンのアクセスキーID（S3バックエンド用） |
| `AWS_SECRET_ACCESS_KEY` | R2 APIトークンのシークレットアクセスキー（S3バックエンド用） |
| `CLOUDFLARE_API_TOKEN` | Cloudflare provider用のAPIトークン |
| `VULTR_API_KEY` | Vultr provider用のAPIキー |
| `TF_VAR_github_app_private_key` | 鍵の退避Jobがrepository_dispatchを送信するときに使うGitHub Appの秘密鍵（PEM） |

GitHub providerは`GITHUB_TOKEN`環境変数のトークンを使い、未設定なら`gh auth token`のトークンを使う。

netbirdのリソースを管理する`terraform/netbird/`では、次の環境変数も設定する。

| 環境変数 | 内容 |
| --- | --- |
| `NB_PAT` | netbird provider用の、管理者のサービスユーザーのPAT |

## CIでのapply

mainへのマージでは、`.github/workflows/terraform-apply.yaml`のworkflowが`terraform/`・`terraform/netbird/`の順にapplyする。
applyの後に、SealedSecretを再暗号化するworkflowを実行する。

CIのplan・applyは、GitHub App（リポジトリのvariable`UPDATE_CLIENT_ID`のClient ID）のトークンでGitHub providerを実行する。
GitHub Appには、次のRepository permissionsが必要である。

| 権限 | アクセス | 使うリソース |
| --- | --- | --- |
| Actions | Read-only | environment・deployment branch policyの読み取り |
| Administration | Read and write | environment・deployment branch policyの作成・変更 |
| Environments | Read and write | environmentのシークレット |
| Secrets | Read and write | リポジトリのシークレット |
| Variables | Read and write | リポジトリのvariable |

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

## CIのシークレットの更新

`terraform/`は、CIが使うCloudflareのAPIトークン・netbirdのPAT・VultrのAPIキーを、GitHubのシークレットに登録する。
値は次の環境変数で渡す。

| 環境変数 | 登録先のenvironment・シークレット |
| --- | --- |
| `TF_VAR_cloudflare_api_token_read_only` | `terraform-plan`の`CLOUDFLARE_API_TOKEN`（読み取り専用のAPIトークン） |
| `TF_VAR_cloudflare_api_token_read_write` | `terraform-apply`の`CLOUDFLARE_API_TOKEN`（読み書きできるAPIトークン） |
| `TF_VAR_netbird_pat_read_only` | `terraform-plan`の`NB_PAT`（読み取り専用のサービスユーザーのPAT） |
| `TF_VAR_netbird_pat_read_write` | `terraform-apply`の`NB_PAT`（管理者のサービスユーザーのPAT） |
| `TF_VAR_vultr_api_key` | リポジトリの`VULTR_API_KEY`（`VULTR_API_KEY`環境変数と同じ値） |

CIのplan・applyはこの5つを設定しないため、Terraformは登録済みのシークレットの値の変更を無視する。
このため、この5つは、シークレットを登録・更新するapplyでだけ設定する。
変数を設定しない場合、まだ登録されていないシークレットには空文字列が登録される。

登録済みのシークレットを更新する場合は、新しい値を環境変数に設定し、対象のシークレットに`-replace`を指定して手元からapplyする。

| シークレット | `-replace`に指定するリソース |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | `github_actions_environment_secret.terraform_ci_cloudflare_api_token["<environment>"]` |
| `NB_PAT` | `github_actions_environment_secret.terraform_ci_netbird_pat["<environment>"]` |
| `VULTR_API_KEY` | `github_actions_secret.vultr_api_key` |

`<environment>`は`terraform-plan`か`terraform-apply`である。
たとえば2つのenvironmentの`NB_PAT`を更新する場合は、次のように実行する。

```sh
mise run tf apply \
  -replace='github_actions_environment_secret.terraform_ci_netbird_pat["terraform-plan"]' \
  -replace='github_actions_environment_secret.terraform_ci_netbird_pat["terraform-apply"]'
```

GitHub Appの秘密鍵（`UPDATE_PRIVATE_KEY`）とClient ID（`UPDATE_CLIENT_ID`）は、CIのplan・applyにも値があるため、`-replace`を指定せずに更新できる。
