locals {
  deployment_id = basename(path.cwd)
  file_name     = "talos-${local.deployment_id}-${var.image.version}-${var.image.platform}-${var.image.arch}.img"
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.image.version
  filters = {
    names = [
      "iscsi-tools",
      "nfs-utils",
      "qemu-guest-agent",
      "trident-iscsi-tools",
      "usb-modem-drivers",
      "util-linux-tools",
    ]
  }
}

locals {
  proxmox_extensions   = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
  baremetal_extensions = [for name in local.proxmox_extensions : name if name != "siderolabs/qemu-guest-agent"]
}

resource "talos_image_factory_schematic" "proxmox" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = local.proxmox_extensions
        }
      }
    }
  )
}

resource "talos_image_factory_schematic" "baremetal" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = local.baremetal_extensions
        }
      }
    }
  )
}

locals {
  image_combinations = toset([for _, v in local.proxmox_nodes : "${v.host_node}_base"])

  # Installer image used by `talosctl upgrade`. It must embed the same
  # schematic as the boot image, otherwise a reinstall wipes the system
  # extensions (iscsi-tools, nfs-utils...).
  installer_image_proxmox   = "${trimprefix(var.image.factory_url, "https://")}/metal-installer/${talos_image_factory_schematic.proxmox.id}:${var.image.version}"
  installer_image_baremetal = "${trimprefix(var.image.factory_url, "https://")}/metal-installer/${talos_image_factory_schematic.baremetal.id}:${var.image.version}"
}

resource "proxmox_virtual_environment_download_file" "this" {

  for_each = {
    for combo in local.image_combinations :
    combo => combo
  }

  node_name    = split("_", each.key)[0]
  content_type = "iso"
  datastore_id = var.image.proxmox_datastore
  file_name    = local.file_name

  url                     = "${var.image.factory_url}/image/${talos_image_factory_schematic.proxmox.id}/${var.image.version}/${var.image.platform}-${var.image.arch}.raw.gz"
  decompression_algorithm = "gz"
  overwrite               = false
}
