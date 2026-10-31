variable "github_token" {
  description = "GitHub providerのトークン（未設定ならGITHUB_TOKEN環境変数か`gh auth token`を使う）"
  type        = string
  default     = null
  sensitive   = true
}
