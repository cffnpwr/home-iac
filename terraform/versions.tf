terraform {
  required_version = "1.16.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "2.33.2"
    }
  }
}

locals {
  talos_version        = "v1.14.4"
  kubernetes_version   = "1.36.5"
  cilium_chart_version = "1.20.3"
  argocd_chart_version = "10.10.5"
}
