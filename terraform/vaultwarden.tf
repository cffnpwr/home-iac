locals {
  vaultwarden_hostname = "vaultwarden.${data.cloudflare_zone.cffnpwr_dev.name}"
  # NOTE: vaultwardenがDOMAINから生成するSSOのコールバック。クライアントの種類ごとの転送先へは、vaultwardenが転送
  vaultwarden_access_redirect_uri = "https://${local.vaultwarden_hostname}/identity/connect/oidc-signin"
}

resource "cloudflare_dns_record" "vaultwarden" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = local.vaultwarden_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.home.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_zero_trust_access_application" "vaultwarden" {
  account_id                = local.cloudflare_account_id
  name                      = "vaultwarden"
  type                      = "saas"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.onetimepin.id]
  auto_redirect_to_identity = true
  policies = [{
    id         = cloudflare_zero_trust_access_policy.allowed_emails.id
    precedence = 1
  }]
  saas_app = {
    auth_type     = "oidc"
    redirect_uris = [local.vaultwarden_access_redirect_uri]
    # NOTE: vaultwardenのSSO_PKCEは既定で有効。セッションはAccessのrefresh tokenで延長
    grant_types = ["authorization_code_with_pkce", "refresh_tokens"]
    scopes      = ["openid", "email", "profile"]
    # NOTE: Web Vaultは有効期限まで5分を切ったaccess tokenを更新するため、5分より長くする
    access_token_lifetime = "15m"
    refresh_token_options = {
      # NOTE: グローバルなセッションの有効期間（既定の24時間）より長くしても、グローバルなセッションが優先される
      lifetime = "24h"
    }
  }
}

# NOTE: Litestreamが複製するDB
resource "cloudflare_r2_bucket" "vaultwarden_db" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-vaultwarden-db"
}

resource "cloudflare_account_token" "vaultwarden_db" {
  account_id = local.cloudflare_account_id
  name       = "vaultwarden-db"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.vaultwarden_db.name}" = "*"
    })
  }]
}

# NOTE: vaultwardenのS3バックエンドが置く、添付ファイル・Send・アイコンのキャッシュ
resource "cloudflare_r2_bucket" "vaultwarden_data" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-vaultwarden-data"
}

# NOTE: Web Vaultが、添付ファイルの署名付きURLをブラウザから取得するため
resource "cloudflare_r2_bucket_cors" "vaultwarden_data" {
  account_id  = local.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.vaultwarden_data.name
  rules = [{
    allowed = {
      methods = ["GET"]
      origins = ["https://${local.vaultwarden_hostname}"]
    }
  }]
}

resource "cloudflare_account_token" "vaultwarden_data" {
  account_id = local.cloudflare_account_id
  name       = "vaultwarden-data"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.vaultwarden_data.name}" = "*"
    })
  }]
}
