terraform {
  required_version = "1.16.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.0"
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
