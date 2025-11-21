variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name            = string
    endpoint        = string
    gateway         = string
    talos_version   = string
    proxmox_cluster = string
    flux_enabled    = optional(bool, false)
  })
}

variable "nodes" {
  description = "Configuration for cluster nodes"
  type = map(object({
    host_node     = string
    machine_type  = string
    datastore_id = optional(string, "local-zfs")
    ip            = string
    mac_address   = string
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update = optional(bool, false)
    igpu = optional(bool, false)
  }))
}

variable "image" {
  description = "Talos image configuration"
  type = object({
    factory_url = optional(string, "https://factory.talos.dev")
    schematic = string
    version   = string
    update_schematic = optional(string)
    update_version = optional(string)
    arch = optional(string, "amd64")
    platform = optional(string, "nocloud")
    proxmox_datastore = optional(string, "local")
  })
}

variable "cilium" {
  description = "Cilium configuration"
  type = object({
    helm_release_file  = string
    install = string
  })
}

variable "flux" {
  description = "Flux Git repository configuration"
  type = object({
      path            = optional(string)
      sops_age_key    = optional(string)
  })
  default = {
    path = null
  }
}
