variable "vault_addr" {
  description = "Адрес Vault API. Для локального запуска обычно используется port-forward на http://127.0.0.1:8200."
  type        = string
}

variable "vault_token" {
  description = "Токен с правами настройки auth methods, policies и secrets engines."
  type        = string
  sensitive   = true
}

variable "kubernetes_host" {
  description = "Адрес Kubernetes API, который Vault будет использовать для TokenReview."
  type        = string
}

variable "kubernetes_ca_cert_path" {
  description = "Путь к PEM-файлу CA Kubernetes API."
  type        = string
}

variable "token_reviewer_jwt" {
  description = "JWT service account с правом выполнять TokenReview."
  type        = string
  sensitive   = true
}

variable "app_namespace" {
  description = "Namespace прикладного контура."
  type        = string
  default     = "app"
}

variable "kv_mount_path" {
  description = "Путь KV v2 secrets engine для прикладных секретов."
  type        = string
  default     = "secret"
}

