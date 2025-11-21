resource "local_file" "machine_configs" {
  for_each        = local.talos_enabled ? module.talos[0].machine_config : {}
  content         = each.value.machine_configuration
  filename        = "output/talos-machine-config-${each.key}.yaml"
  file_permission = "0600"
}

resource "local_file" "talos_config" {
  count           = local.talos_enabled ? 1 : 0
  content         = module.talos[0].client_configuration.talos_config
  filename        = "output/talos-config.yaml"
  file_permission = "0600"
}

resource "local_file" "kube_config" {
  count           = local.talos_enabled ? 1 : 0
  content         = module.talos[0].kube_config.kubeconfig_raw
  filename        = "output/kube-config.yaml"
  file_permission = "0600"
}

output "vm_summary" {
  description = "VM summary information"
  value = {
    for k, m in module.vm.vms :
    k => {
      id       = m.id
      name     = m.name
      ip_mode  = m.ip_mode
      ipv4     = try(flatten(m.ipv4_addresses)[0], null)
      ipv4_all = try(flatten(m.ipv4_addresses), [])
      ipv6_all = try(flatten(m.ipv6_addresses), [])
    }
  }
}

output "kube_config" {
  value     = local.talos_enabled ? module.talos[0].kube_config.kubeconfig_raw : null
  sensitive = true
}

output "talos_config" {
  value     = local.talos_enabled ? module.talos[0].client_configuration.talos_config : null
  sensitive = true
}
