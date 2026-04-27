variable "cluster_name" {
  description = "Логическое имя кластера."
  type        = string
}

variable "network_id" {
  description = "Идентификатор VPC-сети."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR-диапазоны, которым разрешён внешний доступ по SSH и к Kubernetes API."
  type        = list(string)
}

variable "allowed_ingress_cidrs" {
  description = "CIDR-диапазоны, которым разрешён внешний доступ к HTTP- и HTTPS-сервисам."
  type        = list(string)
}
