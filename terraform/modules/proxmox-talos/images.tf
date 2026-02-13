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
      "usb-modem-drivers",
      "util-linux-tools",
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
        }
      }
    }
  )
}

locals {
  image_combinations = toset([for _, v in var.nodes : "${v.host_node}_base"])
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

  url                     = "${var.image.factory_url}/image/${talos_image_factory_schematic.this.id}/${var.image.version}/${var.image.platform}-${var.image.arch}.raw.gz"
  decompression_algorithm = "gz"
  overwrite               = false
}
