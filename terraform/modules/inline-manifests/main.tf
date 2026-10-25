data "helm_template" "cilium" {
  name         = var.cilium_chart.release_name
  repository   = var.cilium_chart.repository
  chart        = var.cilium_chart.chart
  version      = var.cilium_chart.version
  namespace    = var.cilium_chart.namespace
  kube_version = var.kubernetes_version
  values       = [var.cilium_chart.values]
}

data "helm_template" "argocd" {
  name         = var.argocd_chart.release_name
  repository   = var.argocd_chart.repository
  chart        = var.argocd_chart.chart
  version      = var.argocd_chart.version
  namespace    = var.argocd_chart.namespace
  kube_version = var.kubernetes_version
  values       = [var.argocd_chart.values]
}
