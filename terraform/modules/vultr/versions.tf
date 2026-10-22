terraform {
  required_version = "1.16.6"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
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
    vultr = {
      source  = "vultr/vultr"
      version = "2.33.2"
    }
  }
}
