output "vms_summary" {
  description = "Etat synthétique de chaque VM"
  value = {
    for k, m in module.vm :
    k => {
      id        = m.id
      name      = m.name
      ip_mode   = m.ip_mode
      ipv4      = try(m.ipv4_addresses[1][0], null)
      ipv4_all  = flatten(m.ipv4_addresses)
      ipv6_all  = flatten(m.ipv6_addresses)
    }
  }
}
