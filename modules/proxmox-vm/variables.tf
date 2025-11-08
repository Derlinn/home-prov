variable "pve_node" {
  type        = string
  description = "Proxmox node where this VM will be created"
}

variable "pve_datastore" {
  type        = string
  description = "Datastore used to store the VM disk volumes"
}

variable "pve_snippets_datastore" {
  type        = string
  description = "Datastore with 'snippets' content type enabled for cloud-init configs"
}

variable "pve_bridge" {
  type        = string
  description = "Network bridge that the VM network device will attach to"
}

variable "name" {
  type        = string
  description = "Name of the VM (used as hostname and Proxmox VM name)"
}

variable "domain" {
  type        = string
  description = "DNS domain appended to hostname for FQDN"
}

variable "cpu" {
  type        = number
  description = "Number of CPU cores to assign to this VM"
}

variable "mem_mb" {
  type        = number
  description = "Memory allocated to this VM in megabytes"
}

variable "disk_gb" {
  type        = number
  description = "Disk size in gigabytes"
}

variable "ip_cidr" {
  type        = string
  description = "IPv4 addressing mode: 'dhcp' or CIDR format (x.x.x.x/yy)"
}

variable "gw_ip" {
  type        = string
  default     = null
  description = "IPv4 gateway for static mode (ignored when IP is DHCP)"
}

variable "ssh_pubkey" {
  type        = string
  default     = ""
  description = "SSH public key injected into cloud-init authorized_keys"
}

variable "ci_user" {
  type        = string
  description = "Default cloud-init user account name"
}

variable "vm_id" {
  type        = number
  description = "Unique Proxmox integer VM ID"
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Additional user-defined Proxmox tags for this VM"
}

variable "template_tags" {
  type        = list(string)
  description = "Tags used to match the template to clone"
}
