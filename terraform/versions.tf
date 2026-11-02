terraform {
  required_version = "1.17.1"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.2"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "2.33.2"
    }
  }
}

locals {
  # NOTE: 変更するとtalos_machineが各ノードのTalosをその場でアップグレードする
  talos_version = "v1.14.4"
  # NOTE: machine configの生成に使う互換性の基準。クラスタの作成時のバージョンに固定し、Talosのアップグレードでは変更しない
  talos_config_version = "v1.14.4"
  # NOTE: 変更するとtalos_clusterがupgrade-k8sの手順でKubernetesをアップグレードする
  kubernetes_version = "1.36.5"
}
