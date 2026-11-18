provider "cloudflare" {}

provider "external" {}

provider "github" {
  owner = "cffnpwr"
  # NOTE: CIのplanにおけるGITHUB_TOKENはtfcmt用のActionsトークンのため、変数で明示的に指定
  token = var.github_token
}

provider "helm" {}

provider "local" {}

provider "random" {}

provider "talos" {}

provider "tls" {}

provider "vultr" {}
