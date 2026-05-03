output "domain_name" {
  description = "Базовый домен edge-контура."
  value       = local.domain_name
}

output "ingress_hostnames" {
  description = "Hostnames, которые должны указывать на ingress NLB."
  value       = local.ingress_hostnames
}

output "hosts_file_entries" {
  description = "Строки для /etc/hosts или локального DNS при dns_mode=hosts."
  value = [
    for hostname in sort(values(local.ingress_hostnames)) :
    "${var.ingress_external_ip} ${hostname}"
  ]
}

output "dns_zone_id" {
  description = "Cloud DNS zone ID, если zone создана или передана."
  value       = local.dns_zone_id
}

output "cloudflare_record_hostnames" {
  description = "Hostnames, которыми управляет Cloudflare DNS, если dns_provider=cloudflare."
  value       = local.cloudflare_dns_managed ? sort(values(local.ingress_hostnames)) : []
}

output "cdn_hostname" {
  description = "Публичное имя CDN endpoint."
  value       = var.cdn_enabled ? local.cdn_hostname : null
}

output "cdn_provider_cname" {
  description = "Provider CNAME, на который нужно направить публичную CNAME-запись CDN hostname."
  value       = var.cdn_enabled ? yandex_cdn_resource.frontend[0].provider_cname : null
}

output "cdn_certificate_manager_id" {
  description = "Certificate Manager certificate ID, используемый CDN."
  value       = local.certificate_id
}
