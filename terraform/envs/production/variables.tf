variable "proxmox" {
  type = object({
    name         = string
    cluster_name = string
    endpoint     = string
    insecure     = bool
    username     = string
    api_token    = string
  })
  sensitive = true
}

variable "enable_talos_config" {
  description = "Enable Talos cluster configuration and bootstrapping"
  type        = bool
  default     = true
}

variable "flux" {
  description = "Configuration for the Flux GitOps setup."
  type = object({
    url                     = string
    author_name             = optional(string, "FluxCD")
    author_email            = optional(string, "fluxcd@fluxcd.io")
    branch                  = optional(string, "main")
    commit_message_appendix = optional(string, "")
    ssh_private_key         = string
    ssh_username            = optional(string, "git")
  })
  sensitive = true
}

variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name               = string
    endpoint           = string
    gateway            = optional(string)
    talos_version      = string
    proxmox_cluster    = string
    flux_enabled       = optional(bool, false)
    kubernetes_version = string
  })
  default  = null
  nullable = true
}

variable "talos_nodes" {
  description = "Talos nodes definition for the cluster"
  type = map(object({
    provisioning  = optional(string, "proxmox")
    host_node     = string
    machine_type  = string
    datastore_id  = optional(string, "local-zfs")
    ip            = optional(string)
    mac_address   = optional(string)
    vm_id         = optional(number)
    cpu           = optional(number)
    ram_dedicated = optional(number)
    update        = optional(bool, false)
    igpu          = optional(bool, false)
    size_disk     = optional(number, 20)
    install_disk  = optional(string)
    # USB passthrough. Set host = "vendor:product" or mapping = datacenter mapping name.
    usb_devices = optional(list(object({
      host    = optional(string)
      mapping = optional(string)
      usb3    = optional(bool, false)
    })), [])
  }))
  default = {}
}

variable "k8s_bootstrap" {
  description = "Enable Kubernetes cluster bootstrapping after Talos installation"
  type        = bool
  default     = true
}

variable "sops_age_key_path" {
  description = "Path of the file for the SOPS key"
  type        = string
}

variable "wait_for_cluster_health" {
  description = "Run the post-apply cluster health check and fetch the kubeconfig. Set to false when talos_nodes only declares a subset of an already-running cluster."
  type        = bool
  default     = true
}

variable "default_ssh_pubkey" {
  type        = string
  default     = ""
  description = "Default SSH public key if a per-VM key is not provided"
}

variable "vms" {
  description = "Map of VM definitions to instantiate"
  type = map(object({
    host_node = string
    cpu : number
    mem_mb : number
    disk_gb : number
    vm_id : number
    ip_cidr : string
    gw_ip : string
    tags : list(string)
    mac_address : optional(string)
    datastore_id = optional(string, "local-zfs")
    pve_snippets_datastore : optional(string, "local-zfs")
    pve_bridge : optional(string, "vmbr0")

    domain : optional(string, "home.arpa")
    ssh_pubkey : optional(string)
    ci_user : optional(string)
    template_tags : optional(list(string))
  }))
  default = {}
}
