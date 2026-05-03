variable "yc_token" {
  description = "IAM-токен Yandex Cloud. При необходимости может быть передан через TF_VAR_yc_token."
  type        = string
  sensitive   = true
  default     = null
}

variable "yc_cloud_id" {
  description = "Идентификатор облака Yandex Cloud."
  type        = string
}

variable "yc_folder_id" {
  description = "Идентификатор каталога Yandex Cloud."
  type        = string
}

variable "yc_zone" {
  description = "Зона доступности по умолчанию для всех узлов кластера."
  type        = string
  default     = "ru-central1-a"
}

variable "yc_region" {
  description = "Регион Yandex Cloud для региональных ресурсов, например target group сетевого балансировщика."
  type        = string
  default     = "ru-central1"
}

variable "cluster_name" {
  description = "Логическое имя кластера."
  type        = string
}

variable "vm_prefix" {
  description = "Префикс для автоматически создаваемых виртуальных машин."
  type        = string
}

variable "network_name" {
  description = "Необязательное имя VPC-сети."
  type        = string
  default     = null
}

variable "subnet_name" {
  description = "Необязательное имя подсети."
  type        = string
  default     = null
}

variable "network_cidr" {
  description = "CIDR-блок подсети Kubernetes."
  type        = string

  validation {
    condition     = can(cidrhost(var.network_cidr, 1))
    error_message = "network_cidr должен быть корректным CIDR-блоком."
  }
}

variable "domain_suffix" {
  description = "Базовый доменный суффикс для автоматически формируемых имён узлов."
  type        = string
  default     = "internal"
}

variable "node_count_cp" {
  description = "Количество управляющих узлов control plane."
  type        = number
  default     = 3

  validation {
    condition     = var.node_count_cp >= 3 && var.node_count_cp % 2 == 1
    error_message = "node_count_cp должен быть нечётным числом не меньше 3 для quorum etcd."
  }
}

variable "node_count_worker" {
  description = "Количество worker-узлов."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count_worker >= 2
    error_message = "node_count_worker должен быть не меньше 2, иначе PDB/topology spread не дают реальной устойчивости."
  }
}

variable "ssh_user" {
  description = "Пользователь SSH, от имени которого работает Ansible."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "Содержимое публичного SSH-ключа. Если значение не задано, используется ssh_public_key_path."
  type        = string
  default     = null
}

variable "ssh_public_key_path" {
  description = "Путь к файлу публичного SSH-ключа на машине, где запускается Terraform."
  type        = string
  default     = null
}

variable "ssh_private_key_path" {
  description = "Путь к приватному SSH-ключу для Ansible inventory. Если не задан, выводится из ssh_public_key_path без суффикса .pub."
  type        = string
  default     = null
}

variable "platform_id" {
  description = "Идентификатор платформы Yandex Compute Cloud."
  type        = string
  default     = "standard-v3"
}

variable "image_family" {
  description = "Семейство образов, используемое для всех виртуальных машин."
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "disk_type" {
  description = "Тип загрузочного диска для всех виртуальных машин."
  type        = string
  default     = "network-hdd"
}

variable "control_plane_cores" {
  description = "Количество vCPU для управляющих узлов."
  type        = number
  default     = 2
}

variable "control_plane_memory_gb" {
  description = "Объём памяти в ГБ для управляющих узлов."
  type        = number
  default     = 4
}

variable "control_plane_disk_size_gb" {
  description = "Размер загрузочного диска в ГБ для управляющих узлов."
  type        = number
  default     = 40
}

variable "worker_cores" {
  description = "Количество vCPU для worker-узлов."
  type        = number
  default     = 4
}

variable "worker_memory_gb" {
  description = "Объём памяти в ГБ для worker-узлов."
  type        = number
  default     = 8
}

variable "worker_disk_size_gb" {
  description = "Размер загрузочного диска в ГБ для worker-узлов."
  type        = number
  default     = 60
}

variable "enable_nat" {
  description = "Назначать публичные NAT-адреса узлам кластера для прямого SSH-доступа и загрузки пакетов."
  type        = bool
  default     = true
}

variable "enable_control_plane_nat" {
  description = "Переопределение NAT для control-plane узлов. Для реального контура обычно false при наличии bastion/NAT gateway."
  type        = bool
  default     = null
}

variable "enable_worker_nat" {
  description = "Переопределение NAT для worker-узлов. Если null, используется enable_nat."
  type        = bool
  default     = null
}

variable "allowed_ssh_cidrs" {
  description = "CIDR-диапазоны, которым разрешён доступ по SSH."
  type        = list(string)
  default     = ["203.0.113.10/32"]

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_ssh_cidrs должен содержать только корректные CIDR-блоки."
  }
}

variable "allowed_api_cidrs" {
  description = "CIDR-диапазоны, которым разрешён внешний доступ к HA endpoint Kubernetes API."
  type        = list(string)
  default     = ["203.0.113.10/32"]

  validation {
    condition     = alltrue([for cidr in var.allowed_api_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_api_cidrs должен содержать только корректные CIDR-блоки."
  }
}

variable "allowed_ingress_cidrs" {
  description = "CIDR-диапазоны, которым разрешён доступ к опубликованным HTTP/HTTPS-сервисам."
  type        = list(string)
  default     = ["203.0.113.10/32"]

  validation {
    condition     = alltrue([for cidr in var.allowed_ingress_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_ingress_cidrs должен содержать только корректные CIDR-блоки."
  }
}

variable "allowed_egress_cidrs" {
  description = "CIDR-диапазоны, куда узлам разрешён исходящий трафик. Для bootstrap по умолчанию открыт интернет, production может сузить список через NAT/proxy."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.allowed_egress_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_egress_cidrs должен содержать только корректные CIDR-блоки."
  }
}

variable "control_plane_endpoint_ip" {
  description = "Аварийное переопределение IP-адреса kubeadm controlPlaneEndpoint. По умолчанию используется IP сетевого балансировщика Kubernetes API."
  type        = string
  default     = null
}

variable "ingress_http_node_port" {
  description = "NodePort ingress-nginx для HTTP-трафика."
  type        = number
  default     = 30080

  validation {
    condition     = var.ingress_http_node_port >= 30000 && var.ingress_http_node_port <= 32767
    error_message = "ingress_http_node_port должен быть в Kubernetes NodePort диапазоне 30000-32767."
  }
}

variable "ingress_https_node_port" {
  description = "NodePort ingress-nginx для HTTPS-трафика."
  type        = number
  default     = 30443

  validation {
    condition     = var.ingress_https_node_port >= 30000 && var.ingress_https_node_port <= 32767
    error_message = "ingress_https_node_port должен быть в Kubernetes NodePort диапазоне 30000-32767."
  }
}

variable "preemptible" {
  description = "Deprecated: использовать прерываемые worker-VM, если worker_preemptible не задан явно. Для control-plane не применяется."
  type        = bool
  default     = false
}

variable "control_plane_preemptible" {
  description = "Прерываемость control-plane узлов. Должна оставаться false для HA kubeadm-кластера."
  type        = bool
  default     = false
}

variable "worker_preemptible" {
  description = "Использовать прерываемые worker-узлы. Если null, применяется legacy-переменная preemptible."
  type        = bool
  default     = null
}
