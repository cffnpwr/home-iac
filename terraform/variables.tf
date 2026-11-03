variable "github_token" {
  description = "GitHub providerのトークン（未設定ならGITHUB_TOKEN環境変数か`gh auth token`を使う）"
  type        = string
  default     = null
  sensitive   = true
}

# NOTE: GitHubの画面でしか作れないGitHub Appの秘密鍵の、変数での受け取り
variable "github_app_private_key" {
  description = "鍵の退避Jobがrepository_dispatchを送信するときに使うGitHub Appの秘密鍵（PEM）"
  type        = string
  sensitive   = true
}

# NOTE: CIのplan・applyでは未設定のため、空文字列を既定値にする
#       CIのjobが登録済みのシークレットを空文字列で上書きしないよう、シークレットの値の変更は無視する
variable "netbird_pat_read_only" {
  description = "CIのplanがnetbird providerで使う、読み取り専用のサービスユーザーのPAT"
  type        = string
  default     = ""
  sensitive   = true
}

variable "netbird_pat_read_write" {
  description = "CIのapplyがnetbird providerで使う、管理者のサービスユーザーのPAT"
  type        = string
  default     = ""
  sensitive   = true
}

# NOTE: クライアントはPocket IDの管理画面とGoogle Cloudのコンソールでしか作れないため、シークレットを変数で受け取る
variable "pocket_id_access_client_secret" {
  description = "AccessがPocket IDにログインするときに使う、OIDCクライアントのシークレット"
  type        = string
  sensitive   = true
}

variable "google_workspace_access_client_secret" {
  description = "AccessがGoogle Workspaceにログインするときに使う、OAuthクライアントのシークレット"
  type        = string
  sensitive   = true
}

variable "vultr_api_key" {
  description = "CIのplan・applyがVultr providerで使うAPIキー"
  type        = string
  default     = ""
  sensitive   = true
}
