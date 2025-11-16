output "vms" {
  description = "Map of VM infos keyed by VM name."
  value = {
    for name, vm in proxmox_virtual_environment_vm.this :
    name => {
      id              = vm.vm_id
      name            = vm.name
      ip_mode         = var.vms[name].ip_cidr == "dhcp" ? "dhcp" : var.vms[name].ip_cidr
      ipv4_addresses  = tolist(vm.ipv4_addresses)
      ipv6_addresses  = tolist(vm.ipv6_addresses)
    }
  }
}
