variable "network_name" {
  description = "Имя VPC-сети."
  type        = string
}

variable "subnet_name" {
  description = "Имя подсети Kubernetes."
  type        = string
}

variable "zone" {
  description = "Зона доступности, в которой создаётся подсеть."
  type        = string
}

variable "network_cidr" {
  description = "CIDR-блок, назначаемый подсети."
  type        = string
}
