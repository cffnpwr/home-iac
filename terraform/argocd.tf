locals {
  argocd_hostname            = "argocd.${data.cloudflare_zone.cffnpwr_dev.name}"
  argocd_access_redirect_uri = "https://${local.argocd_hostname}/auth/callback"
}

resource "cloudflare_zero_trust_access_policy" "argocd" {
  account_id = local.cloudflare_account_id
  name       = "argocd"
  decision   = "allow"
  include = [
    {
      oidc = {
        identity_provider_id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
        claim_name           = "groups"
        claim_value          = "app-argocd"
      }
    },
    {
      gsuite = {
        identity_provider_id = var.google_workspace_access_identity_provider_id
        email                = "app-argocd@${data.cloudflare_zone.cffnpwr_dev.name}"
      }
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id = local.cloudflare_account_id
  name       = "argocd"
  type       = "saas"
  allowed_idps = [
    cloudflare_zero_trust_access_identity_provider.pocket_id.id,
    var.google_workspace_access_identity_provider_id,
  ]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.argocd.id
    precedence = 1
  }]
  saas_app = {
    auth_type     = "oidc"
    redirect_uris = [local.argocd_access_redirect_uri]
    # NOTE: セッションはAccessのrefresh tokenで延長
    grant_types = ["authorization_code_with_pkce", "refresh_tokens"]
    # NOTE: groupsはArgo CDのRBACでロールの割り当てに使用
    scopes = ["openid", "email", "profile", "groups"]
    # NOTE: ID tokenの有効期間はこの値に関係なく5分
    #       Argo CDはaccess tokenの期限を基準にrefreshするため、ID tokenの有効期間に合わせる
    access_token_lifetime = "5m"
    refresh_token_options = {
      # NOTE: グローバルなセッションの有効期間（既定の24時間）より長くしても、グローバルなセッションが優先される
      lifetime = "24h"
    }
  }
}
