locals {
  google_workspace_access_client_id = "937709066647-c1amha8hd8f6onvot149p169ltuspvbu.apps.googleusercontent.com"
}

resource "cloudflare_zero_trust_access_identity_provider" "google_workspace" {
  account_id = local.cloudflare_account_id
  name       = "Google Workspace"
  type       = "google-apps"
  config = {
    client_id     = local.google_workspace_access_client_id
    client_secret = var.google_workspace_access_client_secret
    apps_domain   = data.cloudflare_zone.cffnpwr_dev.name
    # NOTE: vaultwardenに渡すクレーム
    claims       = ["email_verified"]
    pkce_enabled = true
  }
}
