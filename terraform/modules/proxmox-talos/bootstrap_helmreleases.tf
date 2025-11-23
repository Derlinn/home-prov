locals {
  flux_git_path = coalesce(var.flux.path, "./clusters/${var.cluster.name}")

  charts = {
    coredns = {
      helm = yamldecode(var.coredns.helm_release_file)
      oci  = yamldecode(var.coredns.ocirepository_file)
    }
    cilium = {
      helm = yamldecode(var.cilium.helm_release_file)
      oci  = yamldecode(var.cilium.ocirepository_file)
    }
  }

  parsed = {
    for name, c in local.charts :
    name => {
      parts   = split("/", c.oci.spec.url)
      repo    = join("/", slice(split("/", c.oci.spec.url), 0, length(split("/", c.oci.spec.url)) - 1))
      chart   = element(split("/", c.oci.spec.url), length(split("/", c.oci.spec.url)) - 1)
      version = c.oci.spec.ref.tag
      values  = c.helm.spec.values
    }
  }
}

resource "null_resource" "apply_crds" {
  provisioner "local-exec" {
    command = "${path.module}/../../../scripts/apply-crds.sh"
  }

  depends_on = [resource.talos_cluster_kubeconfig.this]
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = local.parsed.cilium.repo
  chart      = local.parsed.cilium.chart
  namespace  = "kube-system"
  version    = local.parsed.cilium.version
  wait       = true
  timeout    = 600
  values     = [yamlencode(local.parsed.cilium.values)]
  depends_on = [resource.null_resource.apply_crds]

  lifecycle { ignore_changes = all }
}

resource "helm_release" "coredns" {
  name       = "coredns"
  repository = local.parsed.coredns.repo
  chart      = local.parsed.coredns.chart
  namespace  = "kube-system"
  version    = local.parsed.coredns.version
  wait       = true
  timeout    = 600
  values     = [yamlencode(local.parsed.coredns.values)]
  depends_on = [helm_release.cilium]

  lifecycle { ignore_changes = all }
}

data "talos_cluster_health" "after_coredns" {
  depends_on           = [helm_release.coredns]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = local.controlplane_ips
  worker_nodes         = local.worker_ips
  endpoints            = data.talos_client_configuration.this.endpoints

  timeouts = { read = "10m" }
}

resource "flux_bootstrap_git" "this" {
  count = var.cluster.flux_enabled ? 1 : 0

  path = local.flux_git_path

  depends_on = [data.talos_cluster_health.after_coredns]
  lifecycle { ignore_changes = all }
}

resource "kubernetes_secret" "sops_age_key" {
  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }
  type = "Opaque"

  data = {
    agekey = var.flux.sops_age_key
  }

  depends_on = [flux_bootstrap_git.this]
}
