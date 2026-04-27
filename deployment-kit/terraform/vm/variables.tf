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
}

variable "node_count_worker" {
  description = "Количество worker-узлов."
  type        = number
  default     = 2
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

variable "allowed_ssh_cidrs" {
  description = "CIDR-диапазоны, которым разрешён доступ по SSH и к Kubernetes API."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ingress_cidrs" {
  description = "CIDR-диапазоны, которым разрешён доступ к опубликованным HTTP/HTTPS-сервисам."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "control_plane_endpoint_ip" {
  description = "Необязательный статический IP-адрес или адрес балансировщика, используемый как kubeadm controlPlaneEndpoint. Если значение не задано, используется приватный IP первого control-plane узла."
  type        = string
  default     = null
}

variable "preemptible" {
  description = "Использовать прерываемые виртуальные машины. Для управляющих узлов Kubernetes обычно отключается."
  type        = bool
  default     = false
}
