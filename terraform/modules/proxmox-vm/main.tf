# Data source: fetch VMs on the specified Proxmox node filtered by tags.
# The first matched VM is expected to be the template used for cloning.
data "proxmox_virtual_environment_vms" "template" {
  node_name = var.pve_node
  tags      = var.template_tags
}

# Compute the template ID from the first VM in the data source results.
# If nothing matches, set to null to avoid hard failures.
locals {
  template_id = try(data.proxmox_virtual_environment_vms.template.vms[0].vm_id, null)
}

# Upload cloud-init user-data as a Proxmox "snippets" file.
# The templatefile renders user_data.tmpl with VM-specific variables.
resource "proxmox_virtual_environment_file" "cloud_user_config" {
  content_type = "snippets"
  datastore_id = var.pve_snippets_datastore
  node_name    = var.pve_node

  source_raw {
    data = templatefile("cloud-init/user_data.tmpl", {
      hostname   = var.name
      domain     = var.domain
      ssh_pubkey = var.ssh_pubkey
      username   = var.ci_user
    })
    file_name = "${var.name}-user-data.yaml"
  }
}

# Upload cloud-init meta-data as a Proxmox "snippets" file.
# Uses NoCloud schema (instance_id and local_hostname).
resource "proxmox_virtual_environment_file" "cloud_meta_config" {
  content_type = "snippets"
  datastore_id = var.pve_snippets_datastore
  node_name    = var.pve_node
  source_raw {
    data = templatefile("cloud-init/meta_data.tmpl",
      {
        instance_id    = sha1(var.name)
        local_hostname = var.name
    })
    file_name = "${var.name}-meta-data.yml"
  }
}

# Define the Proxmox VM cloned from the tag-resolved template.
# Attaches cloud-init via ide2 and applies network and disk settings.
resource "proxmox_virtual_environment_vm" "this" {
  description = "Managed by Terraform"
  vm_id       = var.vm_id
  name        = var.name
  node_name   = var.pve_node
  on_boot     = true
  started     = true
  tags        = concat(var.tags, ["terraform", "live"])

  # CPU topology and features
  cpu {
    type    = "x86-64-v2-AES"
    cores   = var.cpu
    sockets = 1
  }

  agent { enabled = true}
  # Memory allocation (dedicated)
  memory { dedicated = var.mem_mb }

  # Use virtio-scsi single-controller and boot from scsi0
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  # Primary network interface bridged to the specified Proxmox bridge
  network_device {
    bridge = var.pve_bridge
    model  = "virtio"
  }

  # Primary disk on scsi0, with iothread and discard enabled
  disk {
    interface    = "scsi0"
    iothread     = true
    datastore_id = var.pve_datastore
    size         = var.disk_gb
    discard      = "on"
  }

  # Clone settings: source VM is resolved by tags via the data source
  clone {
    vm_id = local.template_id
  }

  # Cloud-init configuration: attach NoCloud drive on ide2 and pass snippet IDs
  initialization {
    datastore_id = var.pve_datastore
    interface    = "ide2"

    user_data_file_id = proxmox_virtual_environment_file.cloud_user_config.id
    meta_data_file_id = proxmox_virtual_environment_file.cloud_meta_config.id

    # IPv4 config: DHCP or static CIDR with gateway
    ip_config {
      ipv4 {
        address = var.ip_cidr == "dhcp" ? "dhcp" : var.ip_cidr
        gateway = var.gw_ip
      }
    }
  }

  # Ignore diffs on network_device to reduce churn from provider-side defaults
  lifecycle { ignore_changes = [network_device] }
}
