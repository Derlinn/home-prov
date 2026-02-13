terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">=0.9.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.61.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "1.19.1"
    }
    flux = {
      source  = "fluxcd/flux"
      version = ">=1.7.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">=3.1.0"
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

  # Authentification via variable d'environnement :
  # export PROXMOX_VE_API_TOKEN="user@pve!token_name=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
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

provider "flux" {
  kubernetes = {
    host                   = var.enable_talos_config ? module.talos[0].kube_host : "https://localhost:6443"
    cluster_ca_certificate = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_ca_certificate)) : ""
    client_certificate     = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_client_certificate)) : ""
    client_key             = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_client_key)) : ""
  }
  git = {
    url                     = var.flux.url
    author_name             = var.flux.author_name
    author_email            = var.flux.author_email
    branch                  = var.flux.branch
    commit_message_appendix = var.flux.commit_message_appendix
    ssh = {
      private_key = file(var.flux.ssh_private_key)
      username    = var.flux.ssh_username
    }
  }
}

provider "kubernetes" {
  host                   = var.enable_talos_config ? module.talos[0].kube_host : "https://localhost:6443"
  cluster_ca_certificate = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_ca_certificate)) : ""
  client_certificate     = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_client_certificate)) : ""
  client_key             = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_client_key)) : ""
}

provider "helm" {
  kubernetes = {
    host                   = var.enable_talos_config ? module.talos[0].kube_host : "https://localhost:6443"
    cluster_ca_certificate = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_ca_certificate)) : ""
    client_certificate     = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_client_certificate)) : ""
    client_key             = var.enable_talos_config ? trimspace(base64decode(module.talos[0].kube_client_key)) : ""
  }
}
