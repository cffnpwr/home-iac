locals {
  netbird_dashboard_hostname = "netbird.${data.cloudflare_zone.cffnpwr_dev.name}"
  netbird_peer_hostname      = "nb.${data.cloudflare_zone.cffnpwr_dev.name}"
  # NOTE: netbirdの組み込みIdP（Dex）が外部IdPに渡す、issuer + /callbackのコールバック
  netbird_access_redirect_uri = "https://${local.netbird_dashboard_hostname}/oauth2/callback"
}

# NOTE: gRPC・relay・STUNはVultrノードで直接受けるため、プロキシしない
resource "cloudflare_dns_record" "netbird_peer" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = local.netbird_peer_hostname
  type    = "A"
  content = module.vultr.ipv4_address
  proxied = false
  # NOTE: Vultrインスタンスの入れ替えでアドレスが変わるため短くする
  ttl = 60
}

resource "cloudflare_zero_trust_access_application" "netbird" {
  account_id                = local.cloudflare_account_id
  name                      = "netbird"
  type                      = "saas"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.onetimepin.id]
  auto_redirect_to_identity = true
  policies = [{
    id         = cloudflare_zero_trust_access_policy.allowed_emails.id
    precedence = 1
  }]
  saas_app = {
    auth_type     = "oidc"
    redirect_uris = [local.netbird_access_redirect_uri]
    grant_types   = ["authorization_code"]
    scopes        = ["openid", "email", "profile"]
  }
}

resource "cloudflare_r2_bucket" "netbird_backup" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-netbird-backup"
}

resource "cloudflare_account_token" "netbird_backup" {
  account_id = local.cloudflare_account_id
  name       = "netbird-backup"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one(data.cloudflare_account_api_token_permission_groups_list.r2_bucket_item_write.result).id
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cloudflare_account_id}_default_${cloudflare_r2_bucket.netbird_backup.name}" = "*"
    })
  }]
}
