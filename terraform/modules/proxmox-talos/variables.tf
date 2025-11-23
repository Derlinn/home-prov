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
}

variable "nodes" {
  description = "Configuration for cluster nodes"
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
}

variable "talos_base_patches" {
  description = "Optional base Talos YAML per machine type. Keys: controlplane, worker. If set, file() is read and merged before dynamic patches."
  type = object({
    controlplane = optional(string)
    worker       = optional(string)
  })
  default = {}
}

variable "image" {
  description = "Talos image configuration"
  type = object({
    factory_url       = optional(string, "https://factory.talos.dev")
    version           = string
    node_name         = string
    arch              = optional(string, "amd64")
    platform          = optional(string, "nocloud")
    proxmox_datastore = optional(string, "local")
  })
}

variable "cilium" {
  description = "Cilium configuration"
  type = object({
    helm_release_file  = string
    ocirepository_file = string
  })
}

variable "coredns" {
  description = "CoreDNS configuration"
  type = object({
    helm_release_file  = string
    ocirepository_file = string
  })
}

variable "flux" {
  description = "Flux Git repository configuration"
  type = object({
    path         = optional(string)
    sops_age_key = optional(string)
  })
  default = {
    path = null
  }
}
