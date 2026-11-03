# NOTE: Pocket IDが、noreply@cffnpwr.devからメールを送るための送信ドメイン
resource "cloudflare_email_sending_subdomain" "cffnpwr_dev" {
  zone_id = data.cloudflare_zone.cffnpwr_dev.zone_id
  name    = data.cloudflare_zone.cffnpwr_dev.name
}

data "cloudflare_account_api_token_permission_groups_list" "email_sending_write" {
  account_id = local.cloudflare_account_id
  name       = "Email%20Sending%20Write"
}
