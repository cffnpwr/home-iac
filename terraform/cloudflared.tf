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
    # NOTE: ingressは1つ以上必須のため、どの公開ルートにも一致しないリクエストへの404を末尾に配置
    ingress = [{
      service = "http_status:404"
    }]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "home" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.home.id
}
