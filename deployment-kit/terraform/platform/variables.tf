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

