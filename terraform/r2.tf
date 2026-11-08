locals {
  cloudflare_account_id = "086a84b440e09bc83330fe07f1966f5d"
  # NOTE: アカウントトークンには説明を設定できないため、ダッシュボードで人が作成したトークンと名前で区別する
  #       他のリポジトリが作成したトークンと区別するため、リポジトリ名も付ける
  cloudflare_account_token_name_prefix = "[managed by terraform] home-iac/"
}

resource "cloudflare_r2_bucket" "sealed_secrets_keys" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-sealed-secrets-keys"
}

data "cloudflare_account_api_token_permission_groups_list" "r2_bucket_item_write" {
  account_id = local.cloudflare_account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Write"
}

resource "cloudflare_account_token" "sealed_secrets_backup" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}sealed-secrets-backup"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.sealed_secrets_keys.name}" = "*"
    })
  }]
}
