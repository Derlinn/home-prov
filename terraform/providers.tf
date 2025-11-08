terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.42.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.pve_endpoint
  insecure = true

  ssh {
    agent    = true
    username = "root"
  }

  # Authentification via variable d’environnement :
  # export PROXMOX_VE_API_TOKEN="user@pve!token_name=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
