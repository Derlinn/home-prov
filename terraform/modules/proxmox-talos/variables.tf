variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name            = string
    endpoint        = string
    gateway         = optional(string)
    talos_version   = string
    proxmox_cluster = string
    flux_enabled    = optional(bool, false)
    # Must mirror tuppr's KubernetesUpgrade CR. Left unset, the provider bakes
    # its own default version into the generated config, which would upgrade
    # the control plane outside of tuppr's control.
    kubernetes_version = string
  })
}

variable "nodes" {
  description = "Configuration for cluster nodes"
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

  validation {
    condition = alltrue([
      for name, def in var.nodes :
      def.provisioning != "proxmox" || (def.mac_address != null && def.vm_id != null && def.cpu != null && def.ram_dedicated != null)
    ])
    error_message = "Nodes with provisioning = \"proxmox\" require mac_address, vm_id, cpu and ram_dedicated."
  }

  validation {
    condition = alltrue([
      for name, def in var.nodes :
      def.provisioning != "baremetal" || def.ip != null
    ])
    error_message = "Nodes with provisioning = \"baremetal\" require ip (the node must already be reachable)."
  }

  validation {
    condition = alltrue([
      for name, def in var.nodes :
      contains(["proxmox", "baremetal"], def.provisioning)
    ])
    error_message = "provisioning must be either \"proxmox\" or \"baremetal\"."
  }
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

variable "wait_for_cluster_health" {
  description = "Run the post-apply cluster health check and fetch the kubeconfig. Set to false when `nodes` only declares a subset of an already-running cluster (e.g. joining new nodes one at a time)."
  type        = bool
  default     = true
}
