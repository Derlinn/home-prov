resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.nodes

  node_name = each.value.host_node

  name        = each.key
  description = each.value.machine_type == "controlplane" ? "Talos Control Plane" : "Talos Worker"
  tags        = each.value.machine_type == "controlplane" ? ["k8s", "control-plane"] : ["k8s", "worker"]
  on_boot     = true
  vm_id       = each.value.vm_id

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.ram_dedicated
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = each.value.mac_address
  }

  dynamic "usb" {
    for_each = each.value.usb_devices
    content {
      host    = usb.value.host
      mapping = usb.value.mapping
      usb3    = usb.value.usb3
    }
  }

  disk {
    datastore_id = each.value.datastore_id
    interface    = "virtio0"
    iothread     = true
    cache        = "writethrough"
    ssd          = true
    file_format  = "raw"
    size         = each.value.size_disk
    file_id      = proxmox_virtual_environment_download_file.this["${each.value.host_node}_base"].id
  }

  boot_order = ["virtio0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  initialization {
    datastore_id = each.value.datastore_id
    ip_config {
      ipv4 {
        address = each.value.ip != null ? "${each.value.ip}/24" : "dhcp"
        gateway = var.cluster.gateway != null ? var.cluster.gateway : null
      }
    }
  }

  # The boot image only matters for the initial install: the node then boots
  # from its own disk and version bumps go through `talosctl upgrade`. Without
  # this, a version or schematic change alters the download URL, hence the
  # file_id, and Proxmox recreates the VM.
  lifecycle {
    ignore_changes = [disk[0].file_id]
  }

  depends_on = [resource.proxmox_virtual_environment_download_file.this]
}
