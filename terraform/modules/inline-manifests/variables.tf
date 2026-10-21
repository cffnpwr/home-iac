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
