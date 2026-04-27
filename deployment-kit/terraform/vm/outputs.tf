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
  description = "Адрес endpoint, используемый как kubeadm controlPlaneEndpoint."
  value       = module.compute.control_plane_vip
}

output "inventory_yaml" {
  description = "Сгенерированный Ansible inventory для созданного кластера."
  value       = module.inventory.inventory_yaml
}
