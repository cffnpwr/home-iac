resource "github_repository_environment" "sealed_secrets_reseal" {
  repository  = "home-iac"
  environment = "sealed-secrets-reseal"

  # NOTE: シークレットを読めるブランチをmainブランチに限定
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "sealed_secrets_reseal_main" {
  repository     = github_repository_environment.sealed_secrets_reseal.repository
  environment    = github_repository_environment.sealed_secrets_reseal.environment
  branch_pattern = "main"
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
  # NOTE: R2のSecret Access KeyはAPIトークンの値をSHA-256でハッシュ化した値
  value = sha256(cloudflare_account_token.sealed_secrets_reseal.value)
}

resource "github_actions_environment_secret" "sealed_secrets_reseal_data_hmac_key" {
  repository  = github_repository_environment.sealed_secrets_reseal.repository
  environment = github_repository_environment.sealed_secrets_reseal.environment
  secret_name = "SEALED_SECRETS_DATA_HMAC_KEY"
  value       = random_bytes.sealed_secrets_data_hmac_key.hex
}

# NOTE: 証明書は封入に使う公開鍵を含む公開してよい値のためvariableに登録
resource "github_actions_environment_variable" "sealed_secrets_reseal_cert" {
  repository    = github_repository_environment.sealed_secrets_reseal.repository
  environment   = github_repository_environment.sealed_secrets_reseal.environment
  variable_name = "SEALED_SECRETS_CERT"
  value         = tls_self_signed_cert.sealed_secrets.cert_pem
}

resource "github_repository_environment" "terraform_apply" {
  repository  = "home-iac"
  environment = "terraform-apply"

  # NOTE: シークレットを読めるブランチをmainブランチに限定
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
      netbird_pat   = var.netbird_pat_read_only
      vultr_api_key = vultr_user.terraform["plan"].api_key
    }
    (github_repository_environment.terraform_apply.environment) = {
      netbird_pat   = var.netbird_pat_read_write
      vultr_api_key = vultr_user.terraform["apply"].api_key
    }
  }

  # NOTE: mainのrootが変数で受け取る値
  terraform_ci_secrets = {
    TALOS_MACHINE_SECRETS      = jsonencode(talos_machine_secrets.this.machine_secrets)
    SEALED_SECRETS_PRIVATE_KEY = tls_private_key.sealed_secrets.private_key_pem
  }
}

# NOTE: applyのS3 backendの認証情報はworkflowがCLOUDFLARE_API_TOKENから作成
resource "github_actions_environment_secret" "terraform_plan_aws_access_key_id" {
  repository  = "home-iac"
  environment = github_repository_environment.terraform_plan.environment
  secret_name = "AWS_ACCESS_KEY_ID"
  value       = cloudflare_account_token.terraform_plan.id
}

resource "github_actions_environment_secret" "terraform_plan_aws_secret_access_key" {
  repository  = "home-iac"
  environment = github_repository_environment.terraform_plan.environment
  secret_name = "AWS_SECRET_ACCESS_KEY"
  # NOTE: R2のSecret Access KeyはAPIトークンの値をSHA-256でハッシュ化した値
  value = sha256(cloudflare_account_token.terraform_plan.value)
}

resource "github_actions_environment_secret" "terraform_netbird_aws_access_key_id" {
  for_each = cloudflare_account_token.terraform_netbird

  repository  = "home-iac"
  environment = each.key
  secret_name = "NETBIRD_AWS_ACCESS_KEY_ID"
  value       = each.value.id
}

resource "github_actions_environment_secret" "terraform_netbird_aws_secret_access_key" {
  for_each = cloudflare_account_token.terraform_netbird

  repository  = "home-iac"
  environment = each.key
  secret_name = "NETBIRD_AWS_SECRET_ACCESS_KEY"
  # NOTE: R2のSecret Access KeyはAPIトークンの値をSHA-256でハッシュ化した値
  value = sha256(each.value.value)
}

resource "github_actions_environment_secret" "terraform_plan_cloudflare_api_token" {
  repository  = "home-iac"
  environment = github_repository_environment.terraform_plan.environment
  secret_name = "CLOUDFLARE_API_TOKEN"
  value       = cloudflare_account_token.terraform_plan.value
}

# NOTE: APIトークンで作成したトークンにはAccount API Tokens Writeを付けられないため、ダッシュボードで作成したトークンを変数で受け取る
resource "github_actions_environment_secret" "terraform_apply_cloudflare_api_token" {
  repository  = "home-iac"
  environment = github_repository_environment.terraform_apply.environment
  secret_name = "CLOUDFLARE_API_TOKEN"
  value       = var.cloudflare_api_token_apply
}

resource "github_actions_environment_secret" "terraform_ci_netbird_pat" {
  for_each = toset(keys(local.terraform_ci_environments))

  repository  = "home-iac"
  environment = each.key
  secret_name = "NB_PAT"
  value       = local.terraform_ci_environments[each.key].netbird_pat
}

resource "github_actions_environment_secret" "terraform_ci_vultr_api_key" {
  for_each = toset(keys(local.terraform_ci_environments))

  repository  = "home-iac"
  environment = each.key
  secret_name = "VULTR_API_KEY"
  value       = local.terraform_ci_environments[each.key].vultr_api_key
}

resource "github_actions_environment_secret" "terraform_ci" {
  for_each = {
    for pair in setproduct(keys(local.terraform_ci_environments), keys(local.terraform_ci_secrets)) :
    "${pair[0]}/${pair[1]}" => {
      environment = pair[0]
      secret_name = pair[1]
    }
  }

  repository  = "home-iac"
  environment = each.value.environment
  secret_name = each.value.secret_name
  value       = local.terraform_ci_secrets[each.value.secret_name]
}

resource "github_actions_environment_variable" "terraform_ci_google_workspace_access_identity_provider_id" {
  for_each = toset(keys(local.terraform_ci_environments))

  repository    = "home-iac"
  environment   = each.key
  variable_name = "GOOGLE_WORKSPACE_ACCESS_IDENTITY_PROVIDER_ID"
  value         = cloudflare_zero_trust_access_identity_provider.google_workspace.id
}

# NOTE: 証明書は公開してよい値のためvariableに登録
resource "github_actions_environment_variable" "terraform_ci_sealed_secrets_cert" {
  for_each = toset(keys(local.terraform_ci_environments))

  repository    = "home-iac"
  environment   = each.key
  variable_name = "SEALED_SECRETS_CERT"
  value         = tls_self_signed_cert.sealed_secrets.cert_pem
}
