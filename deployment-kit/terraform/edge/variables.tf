variable "yc_token" {
  description = "IAM-токен Yandex Cloud. Можно передать через TF_VAR_yc_token."
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
  description = "Зона по умолчанию для провайдера Yandex Cloud."
  type        = string
  default     = "ru-central1-a"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token для управления DNS-записями. Можно передать через TF_VAR_cloudflare_api_token."
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID публичного домена, если dns_provider=cloudflare."
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Логическое имя кластера, используется в именах DNS/CDN-ресурсов."
  type        = string
}

variable "domain_name" {
  description = "Базовый домен стенда. Для приватного старта используется mdp."
  type        = string
  default     = "mdp"

  validation {
    condition     = length(trimspace(var.domain_name)) > 0 && !strcontains(var.domain_name, "://")
    error_message = "domain_name должен быть доменным суффиксом без схемы URL."
  }
}

variable "ingress_external_ip" {
  description = "Внешний IP ingress NLB из terraform/vm output ingress_external_ip."
  type        = string
}

variable "dns_mode" {
  description = "Режим DNS: hosts только выводит записи, private создаёт приватную Cloud DNS zone, public создаёт публичную zone/records."
  type        = string
  default     = "hosts"

  validation {
    condition     = contains(["hosts", "private", "public"], var.dns_mode)
    error_message = "dns_mode должен быть одним из: hosts, private, public."
  }
}

variable "dns_provider" {
  description = "Провайдер DNS-записей: hosts только генерирует hosts-файл, yandex управляет Yandex Cloud DNS, cloudflare управляет Cloudflare DNS."
  type        = string
  default     = "yandex"

  validation {
    condition     = contains(["hosts", "yandex", "cloudflare"], var.dns_provider)
    error_message = "dns_provider должен быть одним из: hosts, yandex, cloudflare."
  }
}

variable "cloudflare_proxied" {
  description = "Включать Cloudflare proxy. Для GitLab/registry должен оставаться false: прямой DNS only на ingress IP."
  type        = bool
  default     = false
}

variable "create_dns_zone" {
  description = "Создавать новую Cloud DNS zone. Если false, используется dns_zone_id."
  type        = bool
  default     = false
}

variable "dns_zone_id" {
  description = "Идентификатор существующей Cloud DNS zone, если create_dns_zone=false."
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "Имя DNS zone с точкой на конце. По умолчанию строится из domain_name."
  type        = string
  default     = null
}

variable "private_network_ids" {
  description = "VPC network IDs, в которых видна private DNS zone."
  type        = list(string)
  default     = []
}

variable "manage_ingress_records" {
  description = "Создавать A-записи для ingress hostnames, если dns_mode не hosts."
  type        = bool
  default     = true
}

variable "manage_cdn_record" {
  description = "Создавать CNAME-запись CDN hostname -> provider_cname, если CDN включён и DNS управляется Terraform."
  type        = bool
  default     = true
}

variable "dns_ttl" {
  description = "TTL DNS-записей в секундах."
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl >= 60
    error_message = "dns_ttl должен быть не меньше 60 секунд."
  }
}

variable "extra_ingress_hostnames" {
  description = "Дополнительные hostnames, которые должны смотреть на ingress NLB."
  type        = map(string)
  default     = {}
}

variable "cdn_enabled" {
  description = "Создавать CDN origin group/resource для frontend."
  type        = bool
  default     = false
}

variable "cdn_hostname" {
  description = "Публичное имя CDN endpoint. По умолчанию cdn.<domain_name>."
  type        = string
  default     = null
}

variable "cdn_origin_hostname" {
  description = "DNS-имя origin, смотрящее на ingress NLB. По умолчанию origin.<domain_name>."
  type        = string
  default     = null
}

variable "cdn_origin_protocol" {
  description = "Протокол CDN -> origin. По умолчанию используется http; https допустим только при валидном production TLS на origin."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https"], lower(var.cdn_origin_protocol))
    error_message = "cdn_origin_protocol должен быть http или https."
  }
}

variable "cdn_origin_host_header" {
  description = "Host header, который CDN отправляет на ingress. По умолчанию app.<domain_name>."
  type        = string
  default     = null
}

variable "cdn_certificate_manager_id" {
  description = "Идентификатор уже выпущенного сертификата Certificate Manager для cdn_hostname."
  type        = string
  default     = null
}

variable "cdn_create_managed_certificate" {
  description = "Автоматически выпустить managed сертификат через DNS_CNAME challenge. Требует public DNS zone под управлением Terraform."
  type        = bool
  default     = false
}

variable "cdn_wait_managed_certificate_validation" {
  description = "Ждать выпуска managed certificate во время apply. Для первого публичного DNS bootstrap можно временно поставить false."
  type        = bool
  default     = true
}

variable "cdn_redirect_http_to_https" {
  description = "Включать redirect HTTP -> HTTPS на CDN, если задан сертификат."
  type        = bool
  default     = true
}

variable "cdn_edge_cache_seconds" {
  description = "Базовый edge cache TTL для CDN, если origin не задаёт свои cache headers."
  type        = number
  default     = 3600

  validation {
    condition     = var.cdn_edge_cache_seconds >= 0
    error_message = "cdn_edge_cache_seconds не может быть отрицательным."
  }
}

variable "cdn_ignore_cookie" {
  description = "Игнорировать cookies в CDN cache key для статического frontend."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Защищать DNS zone и managed certificate от случайного удаления."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Метки Yandex Cloud ресурсов."
  type        = map(string)
  default     = {}
}
