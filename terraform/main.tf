# Define a Terraform module call named "vm"
module "vm" {
  # Path to the Proxmox VM module
  source = "./modules/proxmox-vm"

  # Create one VM per entry in the "vms" map variable
  for_each = var.vms

  # Proxmox infrastructure parameters
  pve_node               = var.pve_node
  pve_datastore          = var.pve_datastore
  pve_snippets_datastore = var.pve_snippets_datastore
  pve_bridge             = var.pve_bridge

  # VM-specific configuration (taken from each map entry)
  name    = each.key
  domain  = each.value.domain
  cpu     = each.value.cpu
  mem_mb  = each.value.mem_mb
  disk_gb = each.value.disk_gb
  vm_id   = each.value.vm_id
  ip_cidr = each.value.ip_cidr
  gw_ip   = each.value.gw_ip
  ci_user = each.value.ci_user

  # Use the VM’s SSH key or a default key if not provided
  ssh_pubkey = coalesce(each.value.ssh_pubkey, var.default_ssh_pubkey)

  # Proxmox and organizational tags
  tags = each.value.tags

  # Template tags used to locate the correct base image
  template_tags = each.value.template_tags
}
