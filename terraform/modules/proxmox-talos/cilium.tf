locals {
  # Reuse the Flux HelmRelease values so Terraform stays in sync. Accept either a path or inline YAML.
  cilium_flux_helmrelease_raw = try(
    file(var.cilium.helm_release_file),
    var.cilium.helm_release_file,
  )
  cilium_flux_helmrelease = yamldecode(local.cilium_flux_helmrelease_raw)
  cilium_flux_values = try(
    local.cilium_flux_helmrelease.spec.values,
    local.cilium_flux_helmrelease.values,
    local.cilium_flux_helmrelease,
  )
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "oci://ghcr.io/home-operations/charts-mirror/"
  chart      = "cilium"
  namespace  = "kube-system"
  wait       = true
  timeout    = 600
  version    = "1.18.4"

  values = [yamlencode(local.cilium_flux_values)]

  depends_on = [data.talos_cluster_kubeconfig.this]
  lifecycle {
    ignore_changes = all
  }
}

data "talos_cluster_health" "after_cilium" {
  depends_on           = [resource.helm_release.cilium]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
  worker_nodes         = [for k, v in var.nodes : v.ip if v.machine_type == "worker"]
  endpoints            = data.talos_client_configuration.this.endpoints
  timeouts = {
    read = "10m"
  }
}
