resource "cloudflare_zero_trust_access_identity_provider" "onetimepin" {
  account_id = local.cloudflare_account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

resource "cloudflare_zero_trust_list" "allowed_emails" {
  account_id = local.cloudflare_account_id
  name       = "Allowed emails"
  type       = "EMAIL"

  lifecycle {
    # NOTE: メールアドレスはダッシュボードで管理
    ignore_changes = [items]
  }
}

resource "cloudflare_zero_trust_access_policy" "allowed_emails" {
  account_id = local.cloudflare_account_id
  name       = "Allowed emails"
  decision   = "allow"
  include = [{
    email_list = { id = cloudflare_zero_trust_list.allowed_emails.id }
  }]
}

data "cloudflare_zero_trust_organization" "this" {
  account_id = local.cloudflare_account_id
}
