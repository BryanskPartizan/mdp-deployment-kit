output "kv_mount_path" {
  description = "Путь KV v2 secrets engine."
  value       = vault_mount.app_kv.path
}

output "kubernetes_auth_path" {
  description = "Путь Kubernetes auth method в Vault."
  value       = vault_auth_backend.kubernetes.path
}

output "configured_vault_roles" {
  description = "Список ролей Vault, привязанных к ServiceAccount приложений."
  value       = keys(vault_kubernetes_auth_backend_role.app)
}

