variable "cluster_name" {
  description = "Логическое имя кластера, используемое в именах балансировщиков."
  type        = string
}

variable "zone" {
  description = "Зона доступности, в которой резервируются внешние IP-адреса балансировщиков."
  type        = string
}

variable "region_id" {
  description = "Регион Yandex Cloud для target group сетевого балансировщика."
  type        = string
  default     = "ru-central1"
}

variable "subnet_id" {
  description = "Идентификатор подсети, в которой находятся узлы Kubernetes."
  type        = string
}

variable "control_planes" {
  description = "Список control-plane узлов, принимающих трафик Kubernetes API."
  type = list(object({
    name = string
    ip   = string
  }))
}

variable "workers" {
  description = "Список worker-узлов, на которых опубликован ingress-nginx через NodePort."
  type = list(object({
    name = string
    ip   = string
  }))
}

variable "ingress_http_node_port" {
  description = "NodePort ingress-nginx для HTTP-трафика."
  type        = number
  default     = 30080
}

variable "ingress_https_node_port" {
  description = "NodePort ingress-nginx для HTTPS-трафика."
  type        = number
  default     = 30443
}

