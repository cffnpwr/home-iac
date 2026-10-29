resource "cloudflare_zero_trust_tunnel_cloudflared" "home" {
  account_id = local.cloudflare_account_id
  name       = "home"
  # NOTE: 公開ルートをTerraformから管理するためのリモート管理
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "home" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.home.id

  config = {
    ingress = [
      {
        hostname = local.netbird_dashboard_hostname
        path     = "^/(api|oauth2)(/|$)"
        service  = "http://netbird-management.netbird.svc.cluster.local"
      },
      {
        hostname = local.netbird_dashboard_hostname
        service  = "http://netbird-dashboard.netbird.svc.cluster.local"
      },
      # NOTE: 管理画面は公開しない
      {
        hostname = local.vaultwarden_hostname
        path     = "^/admin(/|$)"
        service  = "http_status:404"
      },
      {
        hostname = local.vaultwarden_hostname
        service  = "http://vaultwarden.vaultwarden.svc.cluster.local"
      },
      # NOTE: 公開ルートに一致しないリクエストに404を返す、ingressの末尾に必須のルール
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "home" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.home.id
}
