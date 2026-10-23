variable "kubernetes_version" {
  type        = string
  description = "Kubernetesのバージョン"
}

variable "cilium_chart_version" {
  type        = string
  description = "Cilium helm chartのバージョン"
}

variable "argocd_chart_version" {
  type        = string
  description = "ArgoCD helm chartのバージョン"
}

variable "cilium_values" {
  type        = string
  description = "Cilium helmチャートのvalues（YAML）"
}

variable "argocd_values" {
  type        = string
  description = "ArgoCD helmチャートのvalues（YAML）"
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
