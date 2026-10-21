data "helm_template" "cilium" {
  name         = "cilium"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = var.cilium_chart_version
  namespace    = "kube-system"
  kube_version = var.kubernetes_version
  values       = [var.cilium_values]
}

data "helm_template" "argocd" {
  name         = "argocd"
  repository   = "https://argoproj.github.io/argo-helm"
  chart        = "argo-cd"
  version      = var.argocd_chart_version
  namespace    = "argocd"
  kube_version = var.kubernetes_version
  values       = [var.argocd_values]
}
