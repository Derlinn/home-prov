output "id" {
  description = "Numeric VM identifier inside Proxmox."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "Hostname used for the VM."
  value       = proxmox_virtual_environment_vm.this.name
}

output "ip_mode" {
  description = "Either 'dhcp' or the static CIDR requested for the VM."
  value       = var.ip_cidr == "dhcp" ? "dhcp" : var.ip_cidr
}

output "ipv4_addresses" {
  description = "List of IPv4 addresses currently assigned to the VM."
  value       = tolist(proxmox_virtual_environment_vm.this.ipv4_addresses)
}

output "ipv6_addresses" {
  description = "List of IPv6 addresses currently assigned to the VM."
  value       = tolist(proxmox_virtual_environment_vm.this.ipv6_addresses)
}
