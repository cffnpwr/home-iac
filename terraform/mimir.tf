# NOTE: Mimirのブロックとrulerのルール
#       古いブロックの削除はMimir compactorが削除する
resource "cloudflare_r2_bucket" "mimir" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-mimir"
}

resource "cloudflare_account_token" "mimir" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}mimir"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.mimir.name}" = "*"
    })
  }]
}
