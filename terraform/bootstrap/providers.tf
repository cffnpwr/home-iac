provider "cloudflare" {}

provider "github" {
  owner = "cffnpwr"
  token = var.github_token
}

provider "random" {}

provider "talos" {}

provider "tls" {}

# NOTE: APIキーはVULTR_API_KEY環境変数で指定
provider "vultr" {}
