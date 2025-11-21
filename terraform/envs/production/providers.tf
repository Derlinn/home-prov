terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.61.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "1.19.1"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox.endpoint
  insecure = var.proxmox.insecure

  api_token = var.proxmox.api_token
  ssh {
    agent    = true
    username = var.proxmox.username
  }

  # Authentification via variable d’environnement :
  # export PROXMOX_VE_API_TOKEN="user@pve!token_name=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

provider "kubernetes" {
  host = local.talos_enabled ? module.talos[0].kube_config.kubernetes_client_configuration.host : null
  client_certificate = local.talos_enabled ? base64decode(module.talos[0].kube_config.kubernetes_client_configuration.client_certificate) : null
  client_key = local.talos_enabled ? base64decode(module.talos[0].kube_config.kubernetes_client_configuration.client_key) : null
  cluster_ca_certificate = local.talos_enabled ? base64decode(module.talos[0].kube_config.kubernetes_client_configuration.ca_certificate) : null
}

provider "restapi" {
  uri                  = var.proxmox.endpoint
  insecure             = var.proxmox.insecure
  write_returns_object = true

  headers = {
    "Content-Type"  = "application/json"
    "Authorization" = "PVEAPIToken=${var.proxmox.api_token}"
  }
}
