data "cloudflare_zone" "cffnpwr_dev" {
  filter = {
    name = "cffnpwr.dev"
    account = {
      id = local.cloudflare_account_id
    }
  }
}
