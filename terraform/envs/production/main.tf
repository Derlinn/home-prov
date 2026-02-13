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

module "talos" {
  count  = local.talos_enabled ? 1 : 0
  source = "../../modules/proxmox-talos"

  providers = {
    proxmox    = proxmox
    flux       = flux
    helm       = helm
    kubernetes = kubernetes
  }

  image = {
    version   = local.talos_cluster.talos_version
    node_name = local.talos_cluster.proxmox_cluster
  }

  cluster = local.talos_cluster
  nodes   = var.talos_nodes

  talos_base_patches = {
    controlplane = abspath("${path.module}/files/talos-base-controlplane.yaml")
    worker       = abspath("${path.module}/files/talos-base-worker.yaml")
  }
}

locals {
  controlplane_ips = [
    for name, def in var.talos_nodes :
    def.ip
    if def.machine_type == "controlplane"
  ]

  worker_ips = [
    for name, def in var.talos_nodes :
    def.ip
    if def.machine_type == "worker"
  ]
}

resource "null_resource" "apply_crds" {
  count = var.enable_talos_config && var.k8s_bootstrap ? 1 : 0

  provisioner "local-exec" {
    command = "${path.module}/../../../scripts/apply-crds.sh"
  }

  depends_on = [module.talos]
}

locals {
  charts = {
    cilium = {
      helm = yamldecode(file("${path.module}/../../../kubernetes/apps/kube-system/cilium/app/helmrelease.yaml"))
      oci  = yamldecode(file("${path.module}/../../../kubernetes/apps/kube-system/cilium/app/ocirepository.yaml"))
    }
    coredns = {
      helm = yamldecode(file("${path.module}/../../../kubernetes/apps/kube-system/coredns/app/helmrelease.yaml"))
      oci  = yamldecode(file("${path.module}/../../../kubernetes/apps/kube-system/coredns/app/ocirepository.yaml"))
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

resource "helm_release" "cilium" {
  count = var.enable_talos_config && var.k8s_bootstrap ? 1 : 0

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
  count = var.enable_talos_config && var.k8s_bootstrap ? 1 : 0

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
  count = var.enable_talos_config && var.k8s_bootstrap ? 1 : 0

  client_configuration = module.talos[0].client_configuration.client_configuration
  control_plane_nodes  = local.controlplane_ips
  worker_nodes         = local.worker_ips
  endpoints            = module.talos[0].client_configuration.endpoints

  timeouts = { read = "10m" }

  depends_on = [helm_release.coredns]
}

resource "kubernetes_namespace" "example" {
  metadata {
    name = "flux-system"
  }
}

resource "kubernetes_secret" "sops_age_key" {
  count = var.enable_talos_config && var.k8s_bootstrap ? 1 : 0

  metadata {
    name      = "sops-age"
    namespace = "flux-system"
    annotations = {
      "replicator.v1.mittwald.de/replicate-to" = "*"
    }
  }

  type = "Opaque"

  data = {
    "age.agekey" = file(var.sops_age_key_path)
  }

  depends_on = [data.talos_cluster_health.after_coredns]
}
