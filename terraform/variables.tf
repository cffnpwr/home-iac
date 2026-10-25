variable "github_token" {
  description = "GitHub providerのトークン（未設定ならGITHUB_TOKEN環境変数か`gh auth token`を使う）"
  type        = string
  default     = null
  sensitive   = true
}

variable "github_app_client_id" {
  description = "鍵の退避Jobがrepository_dispatchを送信するときに使うGitHub AppのClient ID"
  type        = string
}

# NOTE: GitHubの画面でしか作れないGitHub Appの秘密鍵の、変数での受け取り
variable "github_app_private_key" {
  description = "鍵の退避Jobがrepository_dispatchを送信するときに使うGitHub Appの秘密鍵（PEM）"
  type        = string
  sensitive   = true
}
