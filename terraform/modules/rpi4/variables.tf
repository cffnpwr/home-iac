variable "cluster_name" {
  type        = string
  description = "Talosクラスタの名前"
}

variable "cluster_endpoint" {
  type        = string
  description = "kube-apiserverのエンドポイントURL"
}

variable "machine_secrets" {
  type        = any
  description = "talos_machine_secretsのmachine_secrets"
  sensitive   = true
}

variable "client_configuration" {
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  description = "Talos APIへ接続するためのクライアント設定"
  sensitive   = true
}

variable "talos_version" {
  type        = string
  description = "Talosのバージョン"
}

variable "kubernetes_version" {
  type        = string
  description = "machine configに設定するKubernetesのバージョン"
}

variable "config_patches" {
  type        = list(string)
  description = "全ノード共通のmachine configパッチ"
}

variable "inline_manifests" {
  type        = map(string)
  description = "KubeInlineManifestConfigとして埋め込むマニフェスト"
}

variable "address" {
  type        = string
  description = "LAN上の静的IPv4アドレス"
}

variable "prefix_length" {
  type        = number
  description = "LANのプレフィックス長"
}

variable "gateway" {
  type        = string
  description = "デフォルトゲートウェイのIPv4アドレス"
}

variable "nameservers" {
  type        = list(string)
  description = "DNSサーバーのIPアドレス"
}

variable "hostname" {
  type        = string
  description = "ノードのホスト名"
}
