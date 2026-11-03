locals {
  argocd_hostname            = "argocd.${data.cloudflare_zone.cffnpwr_dev.name}"
  argocd_access_redirect_uri = "https://${local.argocd_hostname}/auth/callback"
}

resource "cloudflare_zero_trust_access_policy" "argocd" {
  account_id = local.cloudflare_account_id
  name       = "argocd"
  decision   = "allow"
  include = [{
    oidc = {
      identity_provider_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
      claim_name           = "groups"
      claim_value          = "app-argocd"
    }
  }]
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id   = local.cloudflare_account_id
  name         = "argocd"
  type         = "saas"
  allowed_idps = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.argocd.id
    precedence = 1
  }]
  saas_app = {
    auth_type     = "oidc"
    redirect_uris = [local.argocd_access_redirect_uri]
    grant_types   = ["authorization_code_with_pkce"]
    # NOTE: groupsはArgo CDのRBACでロールの割り当てに使用
    scopes = ["openid", "email", "profile", "groups"]
  }
}
