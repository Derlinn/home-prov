locals {
  version          = var.image.version
  update_version   = coalesce(var.image.update_version, var.image.version)
  schematic        = var.image.schematic
  update_schematic = coalesce(var.image.update_schematic, var.image.schematic)

  deployment_id = basename(path.cwd)
}

data "http" "schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

data "http" "updated_schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.update_schematic
}

locals {
  schematic_id        = jsondecode(data.http.schematic_id.response_body)["id"]
  update_schematic_id = jsondecode(data.http.updated_schematic_id.response_body)["id"]

  image_combinations = toset([
    for _, v in var.nodes :
    "${v.host_node}_${v.update ? "update" : "base"}"
  ])
}

resource "proxmox_virtual_environment_download_file" "this" {
  for_each = {
    for combo in local.image_combinations :
    combo => combo
  }

  node_name    = split("_", each.key)[0]
  content_type = "iso"
  datastore_id = var.image.proxmox_datastore

  file_name = "talos-${local.deployment_id}-${
    split("_", each.key)[1] == "update" ? local.update_version : local.version
  }-${var.image.platform}-${var.image.arch}.img"

  url = "${var.image.factory_url}/image/${
    split("_", each.key)[1] == "update" ? local.update_schematic_id : local.schematic_id
    }/${
    split("_", each.key)[1] == "update" ? local.update_version : local.version
  }/${var.image.platform}-${var.image.arch}.raw.gz"

  decompression_algorithm = "gz"

  lifecycle { ignore_changes = all }
}
