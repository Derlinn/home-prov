output "id" { value = proxmox_virtual_environment_vm.this.vm_id }
output "name" { value = proxmox_virtual_environment_vm.this.name }
output "ip_mode" { value = var.ip_cidr == "dhcp" ? "dhcp" : var.ip_cidr }
