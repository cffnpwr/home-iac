locals {
  pocket_id_access_client_id        = "c73259b0-1191-4277-bead-931c45e3e1b8"
  google_workspace_access_client_id = "937709066647-c1amha8hd8f6onvot149p169ltuspvbu.apps.googleusercontent.com"
}

resource "cloudflare_zero_trust_access_identity_provider" "pocket_id" {
  account_id = local.cloudflare_account_id
  name       = "Pocket ID"
  type       = "oidc"
  config = {
    client_id     = local.pocket_id_access_client_id
    client_secret = var.pocket_id_access_client_secret
    auth_url      = "https://auth.cffnpwr.dev/authorize"
    token_url     = "https://auth.cffnpwr.dev/api/oidc/token"
    certs_url     = "https://auth.cffnpwr.dev/.well-known/jwks.json"
    scopes        = ["openid", "email", "profile", "groups"]
    # NOTE: groupsはAccessのポリシーの条件・email_verifiedはvaultwardenに渡すクレームに使用
    claims       = ["groups", "email_verified"]
    pkce_enabled = true
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "google_workspace" {
  account_id = local.cloudflare_account_id
  name       = "Google Workspace"
  type       = "google-apps"
  config = {
    client_id     = local.google_workspace_access_client_id
    client_secret = var.google_workspace_access_client_secret
    apps_domain   = data.cloudflare_zone.cffnpwr_dev.name
    # NOTE: vaultwardenに渡すクレームに使用
    claims       = ["email_verified"]
    pkce_enabled = true
  }
}

data "cloudflare_zero_trust_organization" "this" {
  account_id = local.cloudflare_account_id
}
