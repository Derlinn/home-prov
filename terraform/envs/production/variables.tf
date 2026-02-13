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
    name            = string
    endpoint        = string
    gateway         = optional(string)
    talos_version   = string
    proxmox_cluster = string
    flux_enabled    = optional(bool, false)
  })
  default  = null
  nullable = true
}

variable "talos_nodes" {
  description = "Talos nodes definition for the cluster"
  type = map(object({
    host_node     = string
    machine_type  = string
    datastore_id  = optional(string, "local-zfs")
    ip            = optional(string)
    mac_address   = string
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update        = optional(bool, false)
    igpu          = optional(bool, false)
    size_disk     = optional(number, 20)
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
