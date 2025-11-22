output "client_configuration" {
  value     = data.talos_client_configuration.this
  sensitive = true
}

output "kube_config" {
  value     = resource.talos_cluster_kubeconfig.this
  sensitive = true
}

output "machine_config" {
  value = data.talos_machine_configuration.this
}

output "kube_host" {
  value = resource.talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
}

output "kube_ca_certificate" {
  value = resource.talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
}

output "kube_client_certificate" {
  value     = resource.talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
  sensitive = true
}

output "kube_client_key" {
  value     = resource.talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
  sensitive = true
}
