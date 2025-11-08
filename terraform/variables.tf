variable "pve_endpoint" {
  type        = string
  description = "Proxmox API endpoint (e.g., https://pve01:8006/api2/json)"
}

variable "pve_node" {
  type        = string
  description = "Proxmox node name where VMs will be deployed"
}

variable "pve_datastore" {
  type        = string
  description = "Proxmox datastore used for VM disks"
}

variable "pve_snippets_datastore" {
  type        = string
  description = "Datastore that supports 'snippets' for cloud-init user/meta-data"
}

variable "pve_bridge" {
  type        = string
  description = "Network bridge attached to VM NICs (e.g., vmbr0)"
}

variable "default_ssh_pubkey" {
  type        = string
  default     = ""
  description = "Default SSH public key if a per-VM key is not provided"
}

variable "vms" {
  description = "Map of VM definitions to instantiate"
  type = map(object({
    cpu : number                 # CPU core count
    mem_mb : number              # Memory size in MB
    disk_gb : number             # Disk size in GB
    vm_id : number               # Unique Proxmox VM ID
    domain : string              # Domain used for FQDN
    ci_user : string             # Cloud-init default user
    ip_cidr : string             # Either 'dhcp' or static CIDR"
    gw_ip : string               # Gateway IP for static networking"
    ssh_pubkey : string          # Optional per-VM SSH pubkey
    tags : list(string)          # VM tags
    template_tags : list(string) # Tags to select the base template
  }))
}
