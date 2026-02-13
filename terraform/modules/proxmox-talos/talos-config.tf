resource "time_sleep" "wait_for_proxmox_boot" {
  create_duration = "30s"

  depends_on = [proxmox_virtual_environment_vm.this]
}

resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_version
}

locals {
  node_ips = {
    for name, def in var.nodes :
    name => def.ip
  }

  controlplane_ips = [
    for name, def in var.nodes :
    local.node_ips[name]
    if def.machine_type == "controlplane"
  ]

  worker_ips = [
    for name, def in var.nodes :
    local.node_ips[name]
    if def.machine_type == "worker"
  ]

  talos_base_controlplane = try(var.talos_base_patches.controlplane != null ? file(var.talos_base_patches.controlplane) : null, null)
  talos_base_worker       = try(var.talos_base_patches.worker != null ? file(var.talos_base_patches.worker) : null, null)
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = values(local.node_ips)
  endpoints            = local.controlplane_ips

  depends_on = [time_sleep.wait_for_proxmox_boot]
}

data "talos_machine_configuration" "this" {
  for_each         = var.nodes
  cluster_name     = var.cluster.name
  cluster_endpoint = "https://${var.cluster.endpoint}:6443"
  talos_version    = var.cluster.talos_version
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = compact(
    concat(
      [each.value.machine_type == "controlplane" ? local.talos_base_controlplane : local.talos_base_worker],
      [
        each.value.machine_type == "controlplane" ?
        templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
          node_name    = each.value.host_node
          cluster_name = var.cluster.proxmox_cluster
        }) :
        templatefile("${path.module}/machine-config/worker.yaml.tftpl", {
          node_name    = each.value.host_node
          cluster_name = var.cluster.proxmox_cluster
        })
      ]
    )
  )
}

resource "talos_machine_configuration_apply" "this" {
  for_each = var.nodes

  node                        = local.node_ips[each.key]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration

  depends_on = [proxmox_virtual_environment_vm.this, time_sleep.wait_for_proxmox_boot]
  lifecycle { replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]] }
}

resource "talos_machine_bootstrap" "this" {
  node                 = local.controlplane_ips[0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [proxmox_virtual_environment_vm.this, time_sleep.wait_for_proxmox_boot, talos_machine_configuration_apply.this]
}

data "talos_cluster_health" "this" {
  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = local.controlplane_ips
  worker_nodes           = local.worker_ips
  endpoints              = data.talos_client_configuration.this.endpoints
  skip_kubernetes_checks = true

  timeouts   = { read = "10m" }
  depends_on = [talos_machine_configuration_apply.this, talos_machine_bootstrap.this]
}

resource "talos_cluster_kubeconfig" "this" {
  node                 = local.controlplane_ips[0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration

  timeouts   = { read = "10m" }
  depends_on = [talos_machine_bootstrap.this, data.talos_cluster_health.this, ]
}
