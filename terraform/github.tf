# NOTE: 入力の値の更新は、手元で-replaceを指定してapplyする
resource "github_actions_environment_secret" "terraform_ci_pocket_id_access_client_secret" {
  for_each = toset(["terraform-plan", "terraform-apply"])

  repository  = "home-iac"
  environment = each.key
  secret_name = "POCKET_ID_ACCESS_CLIENT_SECRET"
  value       = var.pocket_id_access_client_secret

  lifecycle {
    ignore_changes = [value]
  }
}
