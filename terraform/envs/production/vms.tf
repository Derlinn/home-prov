# Pre-existing Proxmox VMs, imported as-is. Standalone on purpose:
# modules/proxmox-vm resolves its clone template by tags, which cannot
# uniquely match here (the VMs share all their tags with debian-13-template).
locals {
  lab_vms = {
    "lin-labo-01" = {
      vm_id  = 101
      cores  = 4
      memory = 8096
      mac    = "BC:24:11:09:47:CC"
      tags   = ["cloud", "debian-13", "template"]
    }
    "lin-komodo" = {
      vm_id   = 100
      cores   = 1
      memory  = 2048
      mac     = "BC:24:11:C5:44:9A"
      on_boot = true
      tags    = ["cloud", "debian-13"]
    }
    "lin-admin-deb" = {
      vm_id   = 103
      cores   = 4
      memory  = 8212
      mac     = "BC:24:11:25:3F:31"
      on_boot = true
      tags    = ["cloud", "debian-13", "template"]
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  for_each = local.lab_vms

  name      = each.key
  node_name = "lin-prx-01"
  vm_id     = each.value.vm_id

  started             = true
  on_boot             = try(each.value.on_boot, false)
  stop_on_destroy     = true
  reboot_after_update = false

  agent {
    enabled = false
  }

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    interface    = "scsi0"
    datastore_id = "zfs-vms"
    size         = 50
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = each.value.mac
  }

  initialization {
    datastore_id = "zfs-vms"
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  boot_order = ["scsi0"]

  vga {
    type = "serial0"
  }

  serial_device {}

  tags = each.value.tags

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      initialization,
    ]
  }
}

# Created standalone instead of through modules/proxmox-vm: snippet upload
# requires root SSH to Proxmox, unavailable from this host. Inline
# initialization lets Proxmox generate cloud-init itself, like 100/101/103.
resource "proxmox_virtual_environment_vm" "lin_dev_01" {
  name        = "lin-dev-01"
  description = "Managed by Terraform"
  node_name   = "lin-prx-01"
  vm_id       = 102

  started             = true
  on_boot             = true
  stop_on_destroy     = true
  reboot_after_update = false

  # Enabled (not just installed): Proxmox only creates the guest-agent
  # virtio channel when this flag is set. Clones inherit it from template
  # 9000, which carries the same flag.
  agent {
    enabled = true
  }

  clone {
    vm_id = 9000
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = "zfs-vms"
    size         = 50
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    datastore_id = "zfs-vms"
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "theo"
      keys     = [var.default_ssh_pubkey]
    }
  }

  boot_order = ["scsi0"]

  tags = ["debian-13", "dev", "live", "terraform"]

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      initialization,
    ]
  }
}
