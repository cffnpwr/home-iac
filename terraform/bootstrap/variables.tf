variable "github_token" {
  description = "GitHub providerのトークン"
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudflare_api_token_apply" {
  description = "CIのapplyがCloudflare providerで使う読み書きできるAPIトークン"
  type        = string
  sensitive   = true
}

variable "netbird_pat_read_only" {
  description = "CIのplanがnetbird providerで使う読み取り専用のサービスユーザーのPAT"
  type        = string
  sensitive   = true
}

variable "netbird_pat_read_write" {
  description = "CIのapplyがnetbird providerで使う管理者のサービスユーザーのPAT"
  type        = string
  sensitive   = true
}

# NOTE: クライアントはGoogle Cloudのコンソールでしか作れないためシークレットを変数で受け取る
variable "google_workspace_access_client_secret" {
  description = "AccessがGoogle Workspaceにログインするときに使うOAuthクライアントのシークレット"
  type        = string
  sensitive   = true
}
