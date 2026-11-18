provider "github" {
  owner = "cffnpwr"
  # NOTE: CIのplanにおけるGITHUB_TOKENはtfcmt用のActionsトークンのため、変数で明示的に指定
  token = var.github_token
}

# NOTE: 管理者のPATはNB_PAT環境変数で指定
provider "netbird" {
  management_url = "https://netbird.cffnpwr.dev"
}
