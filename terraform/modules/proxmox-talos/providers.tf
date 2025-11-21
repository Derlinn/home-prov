terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">=0.60.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">=0.9.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = ">=1.7.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">=3.1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.38.0"
    }
  }
}
