output "security_group_id" {
  description = "Идентификатор группы безопасности, назначаемой узлам кластера."
  value       = yandex_vpc_security_group.this.id
}
