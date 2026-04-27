output "api_external_ip" {
  description = "Внешний IP-адрес HA endpoint Kubernetes API."
  value       = yandex_vpc_address.api.external_ipv4_address[0].address
}

output "ingress_external_ip" {
  description = "Внешний IP-адрес входа HTTP/HTTPS трафика в ingress-nginx."
  value       = yandex_vpc_address.ingress.external_ipv4_address[0].address
}

output "api_load_balancer_id" {
  description = "Идентификатор сетевого балансировщика Kubernetes API."
  value       = yandex_lb_network_load_balancer.api.id
}

output "ingress_load_balancer_id" {
  description = "Идентификатор сетевого балансировщика ingress."
  value       = yandex_lb_network_load_balancer.ingress.id
}

