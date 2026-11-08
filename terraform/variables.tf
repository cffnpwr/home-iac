variable "github_token" {
  description = "GitHub providerのトークン（未設定ならGITHUB_TOKEN環境変数か`gh auth token`を使う）"
  type        = string
  default     = null
  sensitive   = true
}

# NOTE: クライアントはPocket IDの管理画面でしか作れないためシークレットを変数で受け取る
variable "pocket_id_access_client_secret" {
  description = "AccessがPocket IDにログインするときに使う、OIDCクライアントのシークレット"
  type        = string
  sensitive   = true
}

# NOTE: 以下はbootstrapのrootが生成しCIのenvironmentに登録する値
variable "talos_machine_secrets" {
  description = "talos_machine_secretsのmachine_secrets（bootstrapのoutputのtalos_machine_secrets）"
  # NOTE: objectの型で属性を列挙すると、列挙しなかった属性が型の変換で削除され、生成するmachine configが変わるためanyにする
  type      = any
  sensitive = true
}

variable "sealed_secrets_private_key" {
  description = "Sealed Secrets controllerの初期の鍵の秘密鍵（PEM）"
  type        = string
  sensitive   = true
}

variable "sealed_secrets_cert" {
  description = "Sealed Secrets controllerの初期の鍵の証明書（PEM）"
  type        = string
}

variable "google_workspace_access_identity_provider_id" {
  description = "Google WorkspaceのAccessのidentity providerのID"
  type        = string
}
