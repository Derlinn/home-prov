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
  tags = sort(each.value.tags)

  # Template tags used to locate the correct base image
  template_tags = each.value.template_tags
}

locals {
  vm_inventory = {
    for k, m in module.vm :
    k => {
      name         = m.name
      fqdn         = "${m.name}.${var.vms[k].domain}"
      ansible_user = var.vms[k].ci_user
      vm_id        = m.id
      tags         = var.vms[k].tags
      ip_cidr      = var.vms[k].ip_cidr
      ansible_host = try(
        m.ipv4_addresses[1][0],
        try(m.ipv4_addresses[0][0], var.vms[k].ip_cidr == "dhcp" ? null : split("/", var.vms[k].ip_cidr)[0])
      )
    }
  }

  tags_all = distinct(flatten([for v in local.vm_inventory : v.tags]))

  groups_by_tag = {
    for t in local.tags_all :
    t => [for v in local.vm_inventory : v.name if contains(v.tags, t)]
  }
}

resource "terraform_data" "assert_ips" {
  lifecycle {
    precondition {
      condition     = alltrue([for _, v in local.vm_inventory : v.ansible_host != null])
      error_message = "Some VMs do not have IPv4. Waiting required."
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../ansible/inventories/prod/inventory.yml")
  content  = templatefile("${path.module}/../ansible/inventories/inventory.yml.tmpl", {
    vm_inventory  = local.vm_inventory
    groups_by_tag = local.groups_by_tag
  })
  depends_on = [terraform_data.assert_ips]
}
