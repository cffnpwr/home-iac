variable "kubernetes_version" {
  type        = string
  description = "Kubernetesのバージョン"
}

variable "cilium_chart" {
  type = object({
    repository   = string
    chart        = string
    version      = string
    release_name = string
    namespace    = string
    values       = string
  })
  description = "Cilium helm chartのリポジトリ・chart名・バージョン・リリース名・namespace・values（YAML）"
}

variable "argocd_chart" {
  type = object({
    repository   = string
    chart        = string
    version      = string
    release_name = string
    namespace    = string
    values       = string
  })
  description = "ArgoCD helm chartのリポジトリ・chart名・バージョン・リリース名・namespace・values（YAML）"
}

variable "argocd_root_application_source" {
  type = object({
    repo_url = string
    path     = string
  })
  description = "ArgoCDのroot Applicationが同期するGitリポジトリのURLとディレクトリ"
}

variable "sealed_secrets_key" {
  type = object({
    cert_pem        = string
    private_key_pem = string
  })
  description = "Sealed Secrets controllerが使う鍵ペア（PEM）"
  sensitive   = true
}
