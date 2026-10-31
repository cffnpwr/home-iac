resource "github_repository_environment" "sealed_secrets_reseal" {
  repository  = "home-iac"
  environment = "sealed-secrets-reseal"
}

resource "github_actions_environment_secret" "sealed_secrets_reseal_aws_access_key_id" {
  repository  = github_repository_environment.sealed_secrets_reseal.repository
  environment = github_repository_environment.sealed_secrets_reseal.environment
  secret_name = "AWS_ACCESS_KEY_ID"
  value       = cloudflare_account_token.sealed_secrets_reseal.id
}

resource "github_actions_environment_secret" "sealed_secrets_reseal_aws_secret_access_key" {
  repository  = github_repository_environment.sealed_secrets_reseal.repository
  environment = github_repository_environment.sealed_secrets_reseal.environment
  secret_name = "AWS_SECRET_ACCESS_KEY"
  # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値
  value = sha256(cloudflare_account_token.sealed_secrets_reseal.value)
}

resource "github_repository_environment" "terraform_apply" {
  repository  = "home-iac"
  environment = "terraform-apply"

  # NOTE: mainへのマージ後のapplyだけがシークレットを読めるよう、mainブランチに限定
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "terraform_apply_main" {
  repository     = github_repository_environment.terraform_apply.repository
  environment    = github_repository_environment.terraform_apply.environment
  branch_pattern = "main"
}
