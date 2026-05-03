variable "kubeconfig_path" {
  description = "Путь к kubeconfig собранного kubeadm-кластера."
  type        = string
}

variable "vault_namespace" {
  description = "Namespace, в котором устанавливается Vault."
  type        = string
  default     = "security"
}

variable "vault_chart_version" {
  description = "Версия Helm chart HashiCorp Vault."
  type        = string
  default     = "0.32.0"
}

variable "vault_values_path" {
  description = "Путь к values-файлу Vault относительно каталога terraform/platform."
  type        = string
  default     = "../../kubernetes/base/vault-values.yaml"
}

variable "vault_host" {
  description = "Публичный hostname Vault ingress. Пустая строка отключает ingress overlay."
  type        = string
  default     = "vault.pkhco.ru"
}

variable "vault_tls_cluster_issuer" {
  description = "ClusterIssuer, который выпускает TLS-сертификат для Vault ingress."
  type        = string
  default     = "letsencrypt-prod"
}
