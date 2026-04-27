output "vault_namespace" {
  description = "Namespace установленного Vault."
  value       = kubernetes_namespace.security.metadata[0].name
}

output "vault_release_name" {
  description = "Имя Helm release Vault."
  value       = helm_release.vault.name
}

output "vault_auth_service_account" {
  description = "ServiceAccount для настройки Kubernetes auth в Vault."
  value       = kubernetes_service_account.vault_auth.metadata[0].name
}

