output "inline_manifests" {
  description = "Talosのinline manifestとして埋め込むマニフェスト"
  value = {
    cilium = data.helm_template.cilium.manifest
    # NOTE: helm templateはリリース先のNamespaceを出力しない
    argocd = join("---\n", [
      yamlencode({
        apiVersion = "v1"
        kind       = "Namespace"
        metadata   = { name = data.helm_template.argocd.namespace }
      }),
      data.helm_template.argocd.manifest,
    ])
  }
}
