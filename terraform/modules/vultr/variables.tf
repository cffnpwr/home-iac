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

variable "region" {
  type        = string
  description = "インスタンスを作成するVultrのリージョンID"
}

variable "plan" {
  type        = string
  description = "インスタンスのVultrのプランID"
}

variable "hostname" {
  type        = string
  description = "ノードのホスト名"
}

variable "node_taints" {
  type        = map(string)
  description = "ノードに付けるtaint（KubeNodeConfigのtaintsの形式。キーがtaintのキー、値が`<値>:<effect>`）"
}

variable "inbound_rules" {
  type = map(object({
    protocol = string
    port     = string
  }))
  description = "全送信元（IPv4・IPv6）から受信を許可する通信。キーはルールの名前、protocolはtcpまたはudp、portはポート番号か`<開始>:<終了>`の範囲"

  validation {
    condition     = alltrue([for rule in values(var.inbound_rules) : contains(["tcp", "udp"], rule.protocol)])
    error_message = "inbound_rulesのprotocolはtcpまたはudpです。"
  }
}
