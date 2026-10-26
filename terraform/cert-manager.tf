data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = local.cloudflare_account_id
  name       = "DNS%20Write"
}

data "cloudflare_account_api_token_permission_groups_list" "zone_read" {
  account_id = local.cloudflare_account_id
  name       = "Zone%20Read"
}

# NOTE: cert-managerがACMEのDNS-01で使うトークン
resource "cloudflare_account_token" "cert_manager" {
  account_id = local.cloudflare_account_id
  name       = "cert-manager"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id },
      { id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id },
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.cffnpwr_dev.zone_id}" = "*"
    })
  }]
}
