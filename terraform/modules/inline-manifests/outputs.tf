output "inline_manifests" {
  description = "Talosのinline manifestとして埋め込むマニフェスト"
  value = {
    cilium = data.helm_template.cilium.manifest

    argocd = join("---\n", [
      # NOTE: Argo CDのnamespaceの作成
      yamlencode({
        apiVersion = "v1"
        kind       = "Namespace"
        metadata   = { name = data.helm_template.argocd.namespace }
      }),
      data.helm_template.argocd.manifest,
    ])

    argocd-root = yamlencode({
      apiVersion = "argoproj.io/v1alpha1"
      kind       = "Application"
      metadata = {
        name      = "root"
        namespace = data.helm_template.argocd.namespace
      }
      spec = {
        project = "default"
        source = {
          repoURL        = var.argocd_root_application_source.repo_url
          targetRevision = "main"
          path           = var.argocd_root_application_source.path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = data.helm_template.argocd.namespace
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    })
  }
}
