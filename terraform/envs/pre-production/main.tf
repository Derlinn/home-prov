locals {
  talos_enabled = length(var.talos_nodes) > 0
  talos_cluster = coalesce(var.cluster, {
    name            = ""
    endpoint        = ""
    gateway         = ""
    talos_version   = "v1.11.5"
    proxmox_cluster = ""
  })
}

module "vm" {
  source = "../../modules/proxmox-vm"

  default_ssh_pubkey     = var.default_ssh_pubkey
  vms                    = var.vms
}

module "talos" {
  count  = local.talos_enabled ? 1 : 0
  source = "../../modules/proxmox-talos"

  providers = {
    proxmox = proxmox
    flux    = flux
    helm    = helm
    kubernetes = kubernetes
  }

  flux = {
    path = "kubernetes/flux/${local.talos_cluster.name}"
    sops_age_key = file("/home/theo/.config/sops/age/keys.txt")
  }

  image = {
    version = local.talos_cluster.talos_version
    schematic = file("${path.module}/../../modules/proxmox-talos/image/schematic.yaml")
  }

  cilium = {
    install = file("${path.module}/../../modules/proxmox-talos/inline-manifests/cilium-install.yaml")
    helm_release_file = file("${path.module}/../../../kubernetes/apps/kube-system/cilium/app/helmrelease.yaml")
  }

  cluster = local.talos_cluster
  nodes   = var.talos_nodes
}

locals {
  vm_inventory = {
    for k, m in module.vm.vms :
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
  filename = abspath("${path.module}/../../../ansible/inventories/preprod.yml")
  content  = templatefile("${path.module}/../../templates/ansible/inventory.yml.tmpl", {
    vm_inventory  = local.vm_inventory
    groups_by_tag = local.groups_by_tag
  })
  depends_on = [terraform_data.assert_ips]
}
