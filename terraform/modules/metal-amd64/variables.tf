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
  description = "全ノード共通のmachine configパッチ"
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

variable "ephemeral_max_size" {
  type        = string
  description = "EPHEMERALの最大サイズ。残りのシステムディスクの領域はlocal-path-provisionerのユーザーボリュームが使う"
}

variable "extensions" {
  type        = list(string)
  description = "ISOとinstallerに含める公式のsystem extensionの名前（例: siderolabs/intel-ucode）"
}

variable "link_name" {
  type        = string
  description = "LANに接続するインターフェースのTalos上の名前。machine config適用前の初期ネットワークに使う"
}

variable "link_driver" {
  type        = string
  description = "LANに接続するインターフェースのドライバ名"
}

variable "install_disk_selector" {
  type        = string
  description = "Talosをインストールするディスクを選択するCEL式。起動に使うUSBメモリもディスクとして列挙される"
}

variable "secure_boot" {
  type        = bool
  description = "Secure Boot用のISOとinstallerを使うか。GRUBでインストールしたノードは、再インストールしないとSecure Bootへ移行できない"
}

variable "local_path_min_size" {
  type        = string
  description = "local-path-provisionerのユーザーボリュームに必要な最小サイズ。空き領域がこれより小さいとボリュームを作成しない"
}
