output "network_id" {
  description = "Идентификатор созданной VPC-сети."
  value       = module.network.network_id
}

output "subnet_id" {
  description = "Идентификатор созданной подсети."
  value       = module.network.subnet_id
}

output "security_group_id" {
  description = "Группа безопасности, назначаемая узлам кластера."
  value       = module.firewall.security_group_id
}

output "control_planes" {
  description = "Список управляющих узлов и их адресов."
  value       = module.compute.control_planes
}

output "workers" {
  description = "Список worker-узлов и их адресов."
  value       = module.compute.workers
}

output "control_plane_vip" {
  description = "Адрес HA endpoint, используемый как kubeadm controlPlaneEndpoint."
  value       = local.control_plane_endpoint_ip
}

output "api_external_ip" {
  description = "Внешний IP сетевого балансировщика Kubernetes API."
  value       = module.load_balancer.api_external_ip
}

output "ingress_external_ip" {
  description = "Внешний IP сетевого балансировщика ingress."
  value       = module.load_balancer.ingress_external_ip
}

output "api_load_balancer_id" {
  description = "Идентификатор сетевого балансировщика Kubernetes API."
  value       = module.load_balancer.api_load_balancer_id
}

output "ingress_load_balancer_id" {
  description = "Идентификатор сетевого балансировщика ingress."
  value       = module.load_balancer.ingress_load_balancer_id
}

output "inventory_yaml" {
  description = "Сгенерированный Ansible inventory для созданного кластера."
  value       = module.inventory.inventory_yaml
}
