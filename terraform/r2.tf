locals {
  cloudflare_account_id = "086a84b440e09bc83330fe07f1966f5d"
}

resource "cloudflare_r2_bucket" "tfstate" {
  account_id = local.cloudflare_account_id
  name       = "home-iac-tfstate"

  lifecycle {
    # NOTE: 破棄すると全リソースのstateが失われる
    prevent_destroy = true
  }
}
