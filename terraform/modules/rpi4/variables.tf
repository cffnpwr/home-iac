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
  description = "ノードにインストールするTalosのバージョン"
}

variable "talos_config_version" {
  type        = string
  description = "machine configの生成に使うTalosのバージョン"
}

variable "kubernetes_version" {
  type        = string
  description = "machine configに設定するKubernetesのバージョン"
}

variable "config_patches" {
  type        = list(string)
  description = "全ノード共通とcontrol plane共通のmachine configパッチ"
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

variable "node_labels" {
  type        = map(string)
  description = "ノードに付けるラベル"
}

variable "kubeconfig" {
  type        = string
  description = "Talosのアップグレードの前にノードをdrainするためのkubeconfig"
  sensitive   = true
  ephemeral   = true
}
