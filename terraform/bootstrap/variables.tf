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
  description = "CIのplanがnetbird providerで使う読み取り専用サービスユーザーのPAT"
  type        = string
  sensitive   = true
}

variable "netbird_pat_read_write" {
  description = "CIのapplyがnetbird providerで使う管理者サービスユーザーのPAT"
  type        = string
  sensitive   = true
}

# NOTE: クライアントはGoogle Cloudのコンソールでしか作成できないため、シークレットを変数で受け取る
variable "google_workspace_access_client_secret" {
  description = "AccessがGoogle Workspaceにログインするときに使うOAuthクライアントのシークレット"
  type        = string
  sensitive   = true
}

# NOTE: GitHub AppのClient IDと秘密鍵はTerraformで作れないため、変数で受け取る
variable "plan_app_client_id" {
  description = "CIのplanがGitHub provider用のトークン発行に使うGitHub AppのClient ID"
  type        = string
}

variable "plan_app_private_key" {
  description = "CIのplanがGitHub provider用のトークン発行に使うGitHub Appの秘密鍵"
  type        = string
  sensitive   = true
}

variable "apply_app_client_id" {
  description = "CIのapplyがGitHub provider用のトークン発行に使うGitHub AppのClient ID"
  type        = string
}

variable "apply_app_private_key" {
  description = "CIのapplyがGitHub provider用のトークン発行に使うGitHub Appの秘密鍵"
  type        = string
  sensitive   = true
}
