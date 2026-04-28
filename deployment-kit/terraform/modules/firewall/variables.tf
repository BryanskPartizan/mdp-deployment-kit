variable "cluster_name" {
  description = "Логическое имя кластера."
  type        = string
}

variable "network_id" {
  description = "Идентификатор VPC-сети."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR-диапазоны, которым разрешён внешний доступ по SSH."
  type        = list(string)
}

variable "allowed_api_cidrs" {
  description = "CIDR-диапазоны, которым разрешён внешний доступ к Kubernetes API через HA endpoint."
  type        = list(string)
}

variable "allowed_ingress_cidrs" {
  description = "CIDR-диапазоны, которым разрешён внешний доступ к HTTP- и HTTPS-сервисам."
  type        = list(string)
}

variable "allowed_egress_cidrs" {
  description = "CIDR-диапазоны, куда разрешён исходящий трафик с узлов."
  type        = list(string)
}

variable "ingress_http_node_port" {
  description = "NodePort ingress-nginx для HTTP-трафика."
  type        = number
}

variable "ingress_https_node_port" {
  description = "NodePort ingress-nginx для HTTPS-трафика."
  type        = number
}
