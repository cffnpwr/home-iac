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

variable "machine_type" {
  type        = string
  description = "ノードの種類（controlplane・worker）"

  validation {
    condition     = contains(["controlplane", "worker"], var.machine_type)
    error_message = "machine_typeはcontrolplane・workerのいずれかを指定する"
  }
}

variable "config_patches" {
  type        = list(string)
  description = "全ノード共通のmachine configパッチ。control planeの場合はcontrol plane共通のパッチも含める"
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
  description = "EPHEMERALの最大サイズ。nullの場合はディスクの残りの領域をすべて使う"
  default     = null
}

variable "ephemeral_disk_selector" {
  type        = string
  description = "EPHEMERALを置くディスクを選択するCEL式。nullの場合はシステムディスクに置く"
  default     = null
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
  description = "システムディスクに作るlocal-path-provisionerのユーザーボリュームに必要な最小サイズ。空き領域がこれより小さいとボリュームを作成しない。nullの場合はユーザーボリュームを作らない"
  default     = null
}

variable "ceph_osd" {
  type = object({
    disk_selector = string
    min_size      = optional(string)
    max_size      = optional(string)
  })
  description = "RookがCephのOSDに使うraw volumeを置くディスクを選択するCEL式とサイズ。min_size・max_sizeの少なくとも一方が必要。nullの場合はraw volumeを作らない"

  validation {
    condition     = var.ceph_osd == null || try(var.ceph_osd.min_size != null || var.ceph_osd.max_size != null, false)
    error_message = "ceph_osdにはmin_size・max_sizeの少なくとも一方を指定する"
  }
  default = null
}
