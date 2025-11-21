locals {
  flux_git_path = coalesce(
    var.flux.path,
    "./clusters/${var.cluster.name}"
  )
}

resource "flux_bootstrap_git" "this" {
    count = var.cluster.flux_enabled ? 1 : 0

    depends_on = [data.talos_cluster_health.after_cilium]
    path       = local.flux_git_path
}

resource "kubernetes_secret" "sops_age_key" {
  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }

  type = "Opaque"

  data = {
    agekey = base64encode(var.flux.sops_age_key)
  }

    depends_on = [flux_bootstrap_git.this]
}
