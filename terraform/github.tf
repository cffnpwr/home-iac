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

resource "github_repository_environment" "terraform_plan" {
  repository  = "home-iac"
  environment = "terraform-plan"
}

locals {
  terraform_ci_environments = {
    (github_repository_environment.terraform_plan.environment) = {
      cloudflare_api_token = var.cloudflare_api_token_read_only
      netbird_pat          = var.netbird_pat_read_only
    }
    (github_repository_environment.terraform_apply.environment) = {
      cloudflare_api_token = var.cloudflare_api_token_read_write
      netbird_pat          = var.netbird_pat_read_write
    }
  }
}

resource "github_actions_environment_secret" "terraform_ci_aws_access_key_id" {
  for_each = cloudflare_account_token.terraform_ci

  repository  = "home-iac"
  environment = each.key
  secret_name = "AWS_ACCESS_KEY_ID"
  value       = each.value.id
}

resource "github_actions_environment_secret" "terraform_ci_aws_secret_access_key" {
  for_each = cloudflare_account_token.terraform_ci

  repository  = "home-iac"
  environment = each.key
  secret_name = "AWS_SECRET_ACCESS_KEY"
  # NOTE: R2のSecret Access Keyは、APIトークンの値をSHA-256でハッシュ化した値
  value = sha256(each.value.value)
}

# NOTE: 入力の値の更新は、手元で-replaceを指定してapplyする
resource "github_actions_environment_secret" "terraform_ci_cloudflare_api_token" {
  for_each = toset(keys(local.terraform_ci_environments))

  repository  = "home-iac"
  environment = each.key
  secret_name = "CLOUDFLARE_API_TOKEN"
  value       = local.terraform_ci_environments[each.key].cloudflare_api_token

  lifecycle {
    ignore_changes = [value]
  }
}

resource "github_actions_environment_secret" "terraform_ci_netbird_pat" {
  for_each = toset(keys(local.terraform_ci_environments))

  repository  = "home-iac"
  environment = each.key
  secret_name = "NB_PAT"
  value       = local.terraform_ci_environments[each.key].netbird_pat

  lifecycle {
    ignore_changes = [value]
  }
}
