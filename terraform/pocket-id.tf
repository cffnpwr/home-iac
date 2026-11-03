# NOTE: SMTPでのメール送信に使用するパスワードとしてのCloudflare API Tokenを作成
resource "cloudflare_account_token" "pocket_id_smtp" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}pocket-id-smtp"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.email_sending_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*"
    })
  }]
}

# NOTE: PostgreSQLのWALとベースバックアップ
resource "cloudflare_r2_bucket" "pocket_id_db" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-pocket-id-db"
}

resource "cloudflare_account_token" "pocket_id_db" {
  account_id = local.cloudflare_account_id
  name       = "${local.cloudflare_account_token_name_prefix}pocket-id-db"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.pocket_id_db.name}" = "*"
    })
  }]
}
