resource "cloudflare_zero_trust_tunnel_cloudflared" "home" {
  account_id = local.cloudflare_account_id
  name       = "cffnpwr-home"
  # NOTE: 公開ルートをCloudflare Tunnel Ingress Controllerから管理するためのリモート管理
  config_src = "cloudflare"
}

data "cloudflare_account_api_token_permission_groups_list" "cloudflared_write" {
  account_id = local.cloudflare_account_id
  name       = "Cloudflare%20One%20Connector%3A%20cloudflared%20Write"
}

# NOTE: Cloudflare Tunnel Ingress Controllerが、トンネルの公開ルートとDNSレコードの管理に使うトークン
resource "cloudflare_account_token" "cloudflare_tunnel_ingress_controller" {
  account_id = local.cloudflare_account_id
  name       = "cloudflare-tunnel-ingress-controller"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        { id = one(data.cloudflare_account_api_token_permission_groups_list.cloudflared_write.result).id },
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*"
      })
    },
    {
      effect = "allow"
      permission_groups = [
        { id = one(data.cloudflare_account_api_token_permission_groups_list.dns_write.result).id },
        { id = one(data.cloudflare_account_api_token_permission_groups_list.zone_read.result).id },
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.cffnpwr_dev.zone_id}" = "*"
      })
    },
  ]
}
