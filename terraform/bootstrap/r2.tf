locals {
  cloudflare_account_id = "086a84b440e09bc83330fe07f1966f5d"
  # NOTE: アカウントトークンには説明を設定できないためダッシュボードで人が作成したトークンと名前で区別
  #       他のリポジトリが作成したトークンと区別するためリポジトリ名をprefixに付与
  cloudflare_account_token_name_prefix = "[managed by terraform] home-iac/"
}

resource "cloudflare_r2_bucket" "tfstate" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-tfstate"

  lifecycle {
    # NOTE: 破棄するとbootstrap・main・netbirdの全リソースのstateが失われる
    prevent_destroy = true
  }
}

data "cloudflare_account_api_token_permission_groups_list" "r2_bucket_item_read" {
  account_id = local.cloudflare_account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Read"
}

data "cloudflare_account_api_token_permission_groups_list" "r2_bucket_item_write" {
  account_id = local.cloudflare_account_id
  name       = "Workers%20R2%20Storage%20Bucket%20Item%20Write"
}

resource "cloudflare_account_token" "sealed_secrets_reseal" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}sealed-secrets-reseal"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_read.result).id
    }]
    # NOTE: CIによるS3 backendのstateの読み取り用
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.tfstate.name}" = "*"
    })
  }]
}
