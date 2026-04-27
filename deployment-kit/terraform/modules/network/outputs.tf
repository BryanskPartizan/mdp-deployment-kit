output "network_id" {
  description = "Идентификатор созданной VPC-сети."
  value       = yandex_vpc_network.this.id
}

output "subnet_id" {
  description = "Идентификатор созданной подсети."
  value       = yandex_vpc_subnet.this.id
}

output "network_cidr" {
  description = "CIDR подсети, используемой кластером."
  value       = var.network_cidr
}
