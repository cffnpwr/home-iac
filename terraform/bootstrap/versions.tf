terraform {
  required_version = "1.17.1"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.1"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
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
  # NOTE: terraform/versions.tfのtalos_config_versionと同じ値にする
  talos_config_version = "v1.14.4"
}
