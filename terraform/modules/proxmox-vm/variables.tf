variable "default_ssh_pubkey" {
  type        = string
  default     = ""
  description = "Default SSH public key if a per-VM key is not provided"
}

variable "vms" {
  description = "Map of VM definitions to instantiate"
  type = map(object({
    host_node : string
    cpu : number
    mem_mb : number
    disk_gb : number
    vm_id : number
    ip_cidr : string
    gw_ip : string
    tags : list(string)
    mac_address : optional(string)
    datastore_id : string
    pve_snippets_datastore : string
    pve_bridge : optional(string)

    domain : optional(string, "home.arpa")
    ssh_pubkey : optional(string)
    ci_user : optional(string)
    template_tags : optional(list(string))
  }))
}
