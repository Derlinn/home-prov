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

variable "default_ssh_pubkey" {
  type        = string
  default     = ""
  description = "Default SSH public key if a per-VM key is not provided"
}

variable "vms" {
  description = "Map of VM definitions to instantiate"
  type = map(object({
    # Common VM parameters
    host_node     = string        # Proxmox host node
    cpu : number                 # CPU core count
    mem_mb : number              # Memory size in MB
    disk_gb : number             # Disk size in GB
    vm_id : number               # Unique Proxmox VM ID
    ip_cidr : string             # Either 'dhcp' or static CIDR"
    gw_ip : string               # Gateway IP for static networking"
    tags : list(string)          # VM tags
    mac_address : optional(string)    # Optional MAC address
    datastore_id  = optional(string, "local-zfs")
    pve_snippets_datastore : optional(string, "local-zfs")  # Snippets datastore (for cloud-init)
    pve_bridge : optional(string, "vmbr0")    # Network bridge (overrides global if set)

    # Linux (cloud-init + clone)
    domain : optional(string, "home.arpa")              # Domain used for FQDN
    ssh_pubkey : optional(string)                       # Optional per-VM SSH pubkey
    ci_user : optional(string)                          # Cloud-init default user
    template_tags : optional(list(string))              # Tags to select the base template

    # OS selection. Default is 'linux'
    os : optional(string, "linux")

  }))
}

variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name            = string
    endpoint        = string
    gateway         = string
    talos_version   = string
    proxmox_cluster = string
  })
}

variable "talos_nodes" {
  description = "Talos nodes definition for the cluster"
  type = map(object({
    host_node     = string
    machine_type  = string
    datastore_id  = optional(string, "local-zfs")
    ip            = string
    mac_address   = string
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update        = optional(bool, false)
    igpu          = optional(bool, false)
  }))
  default = {}
}
