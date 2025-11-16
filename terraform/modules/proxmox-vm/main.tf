locals {
  vms = var.vms
}

locals {
  # Resolve per-VM overrides or fall back to global defaults.
  vm_settings = {
    for name, cfg in local.vms :
    name => {
      node_name            = cfg.host_node
      datastore_id         = coalesce(cfg.datastore_id, "local-zfs")
      snippets_datastore   = coalesce(cfg.pve_snippets_datastore, "local-zfs", coalesce(cfg.datastore_id, "local-zfs"))
      bridge               = coalesce(cfg.pve_bridge, "vmbr0")
      ssh_pubkey           = coalesce(cfg.ssh_pubkey, var.default_ssh_pubkey, "")
      ip_cidr              = cfg.ip_cidr
      gw_ip                = cfg.gw_ip
      template_tags        = coalesce(cfg.template_tags, [])
      mac_address          = try(cfg.mac_address, null)
    }
  }
}

# Data source: fetch template per VM using its tags.
data "proxmox_virtual_environment_vms" "template" {
  for_each  = local.vm_settings
  node_name = each.value.node_name
  tags      = each.value.template_tags
}

locals {
  template_ids = {
    for name, tpl in data.proxmox_virtual_environment_vms.template :
    name => try(tpl.vms[0].vm_id, null)
  }
}

# Upload cloud-init user-data as a Proxmox "snippets" file for each VM.
resource "proxmox_virtual_environment_file" "cloud_user_config" {
  for_each = local.vms

  content_type = "snippets"
  datastore_id = local.vm_settings[each.key].snippets_datastore
  node_name    = local.vm_settings[each.key].node_name

  source_raw {
    data = templatefile("${path.module}/cloud-init/user_data.tmpl", {
      hostname   = each.key
      domain     = each.value.domain
      ssh_pubkey = local.vm_settings[each.key].ssh_pubkey
      username   = each.value.ci_user
    })
    file_name = "${each.key}-user-data.yaml"
  }
}

# Upload cloud-init meta-data as a Proxmox "snippets" file for each VM.
resource "proxmox_virtual_environment_file" "cloud_meta_config" {
  for_each = local.vms

  content_type = "snippets"
  datastore_id = local.vm_settings[each.key].snippets_datastore
  node_name    = local.vm_settings[each.key].node_name
  source_raw {
    data = templatefile("${path.module}/cloud-init/meta_data.tmpl",
      {
        instance_id    = sha1(each.key)
        local_hostname = each.key
    })
    file_name = "${each.key}-meta-data.yml"
  }
}

# Define the Proxmox VMs cloned from their tag-resolved templates.
resource "proxmox_virtual_environment_vm" "this" {
  for_each = local.vms

  description = "Managed by Terraform"
  vm_id       = each.value.vm_id
  name        = each.key
  node_name   = local.vm_settings[each.key].node_name
  on_boot     = true
  started     = true
  tags        = concat(each.value.tags, ["terraform", "live"])

  cpu {
    type    = "x86-64-v2-AES"
    cores   = each.value.cpu
    sockets = 1
  }

  agent { enabled = true }

  memory { dedicated = each.value.mem_mb }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  network_device {
    bridge      = local.vm_settings[each.key].bridge
    model       = "virtio"
    mac_address = local.vm_settings[each.key].mac_address
  }

  disk {
    interface    = "scsi0"
    iothread     = true
    datastore_id = local.vm_settings[each.key].datastore_id
    size         = each.value.disk_gb
    discard      = "on"
  }

  clone {
    vm_id = local.template_ids[each.key]
  }

  initialization {
    datastore_id = local.vm_settings[each.key].datastore_id
    interface    = "ide2"

    user_data_file_id = proxmox_virtual_environment_file.cloud_user_config[each.key].id
    meta_data_file_id = proxmox_virtual_environment_file.cloud_meta_config[each.key].id

    ip_config {
      ipv4 {
        address = local.vm_settings[each.key].ip_cidr == "dhcp" ? "dhcp" : local.vm_settings[each.key].ip_cidr
        gateway = local.vm_settings[each.key].gw_ip
      }
    }
  }

  lifecycle {
    ignore_changes = [
      ipv4_addresses,
      ipv6_addresses,
      network_interface_names,
      initialization,
    ]
  }
}
