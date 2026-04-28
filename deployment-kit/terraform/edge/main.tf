locals {
  domain_name = trimsuffix(var.domain_name, ".")
  zone_name   = "${trimsuffix(coalesce(var.dns_zone_name, var.domain_name), ".")}."

  # Приватный дефолтный контур стенда. Эти имена используются Helm values и smoke/integration tests.
  ingress_hostnames = merge(
    {
      app      = "app.${local.domain_name}"
      gateway  = "gateway.${local.domain_name}"
      api      = "api.${local.domain_name}"
      gitlab   = "gitlab.${local.domain_name}"
      registry = "registry.${local.domain_name}"
      minio    = "minio.${local.domain_name}"
    },
    var.extra_ingress_hostnames
  )

  cdn_hostname           = coalesce(var.cdn_hostname, "cdn.${local.domain_name}")
  cdn_origin_hostname    = coalesce(var.cdn_origin_hostname, "origin.${local.domain_name}")
  cdn_origin_host_header = coalesce(var.cdn_origin_host_header, local.ingress_hostnames.app)

  dns_managed = var.dns_mode != "hosts" && (var.create_dns_zone || var.dns_zone_id != null)
  dns_zone_id = var.create_dns_zone ? yandex_dns_zone.main[0].id : var.dns_zone_id

  ingress_record_hostnames = toset(distinct(concat(
    values(local.ingress_hostnames),
    var.cdn_enabled ? [local.cdn_origin_hostname] : []
  )))

  certificate_enabled = var.cdn_enabled && (var.cdn_create_managed_certificate || var.cdn_certificate_manager_id != null)
  certificate_id      = var.cdn_enabled && var.cdn_create_managed_certificate ? data.yandex_cm_certificate.cdn[0].id : var.cdn_certificate_manager_id
}

resource "yandex_dns_zone" "main" {
  count = var.create_dns_zone ? 1 : 0

  name                = "${var.cluster_name}-edge-zone"
  description         = "DNS zone for deployment-kit ${var.cluster_name}"
  zone                = local.zone_name
  public              = var.dns_mode == "public"
  private_networks    = var.dns_mode == "private" ? var.private_network_ids : []
  deletion_protection = var.deletion_protection
  labels              = var.labels

  lifecycle {
    precondition {
      condition     = var.dns_mode != "hosts"
      error_message = "create_dns_zone=true требует dns_mode=private или dns_mode=public."
    }
    precondition {
      condition     = var.dns_mode != "private" || length(var.private_network_ids) > 0
      error_message = "Для private DNS zone передайте private_network_ids. Скрипт edge-apply подставляет network_id из terraform/vm outputs."
    }
  }
}

resource "yandex_dns_recordset" "ingress_a" {
  for_each = local.dns_managed && var.manage_ingress_records ? local.ingress_record_hostnames : []

  zone_id = local.dns_zone_id
  name    = "${each.value}."
  type    = "A"
  ttl     = var.dns_ttl
  data    = [var.ingress_external_ip]
}

resource "yandex_cm_certificate" "cdn" {
  count = var.cdn_enabled && var.cdn_create_managed_certificate ? 1 : 0

  name                = "${var.cluster_name}-cdn-${replace(local.cdn_hostname, ".", "-")}"
  domains             = [local.cdn_hostname]
  deletion_protection = var.deletion_protection
  labels              = var.labels

  managed {
    challenge_type = "DNS_CNAME"
  }

  lifecycle {
    precondition {
      condition     = local.dns_managed
      error_message = "cdn_create_managed_certificate=true требует управляемую Cloud DNS zone."
    }
    precondition {
      condition     = var.dns_mode == "public"
      error_message = "Certificate Manager managed certificate через Let's Encrypt требует публичный домен и public DNS zone."
    }
  }
}

resource "yandex_dns_recordset" "cdn_certificate_challenge" {
  count = var.cdn_enabled && var.cdn_create_managed_certificate ? yandex_cm_certificate.cdn[0].managed[0].challenge_count : 0

  zone_id = local.dns_zone_id
  name    = yandex_cm_certificate.cdn[0].challenges[count.index].dns_name
  type    = yandex_cm_certificate.cdn[0].challenges[count.index].dns_type
  ttl     = 60
  data    = [yandex_cm_certificate.cdn[0].challenges[count.index].dns_value]
}

data "yandex_cm_certificate" "cdn" {
  count = var.cdn_enabled && var.cdn_create_managed_certificate ? 1 : 0

  depends_on      = [yandex_dns_recordset.cdn_certificate_challenge]
  certificate_id  = yandex_cm_certificate.cdn[0].id
  wait_validation = true
}

resource "yandex_cdn_origin_group" "frontend" {
  count = var.cdn_enabled ? 1 : 0

  name          = "${var.cluster_name}-frontend-origin"
  provider_type = "ourcdn"
  use_next      = true

  origin {
    source  = local.cdn_origin_hostname
    enabled = true
  }
}

resource "yandex_cdn_resource" "frontend" {
  count = var.cdn_enabled ? 1 : 0

  cname           = local.cdn_hostname
  active          = true
  provider_type   = "ourcdn"
  origin_protocol = lower(var.cdn_origin_protocol)
  origin_group_id = yandex_cdn_origin_group.frontend[0].id
  labels          = var.labels

  dynamic "ssl_certificate" {
    for_each = local.certificate_enabled ? [local.certificate_id] : []
    content {
      type                   = "certificate_manager"
      certificate_manager_id = ssl_certificate.value
    }
  }

  options {
    custom_host_header     = local.cdn_origin_host_header
    edge_cache_settings    = var.cdn_edge_cache_seconds
    ignore_cookie          = var.cdn_ignore_cookie
    gzip_on                = true
    fetched_compressed     = true
    redirect_http_to_https = local.certificate_enabled ? var.cdn_redirect_http_to_https : false
  }
}

resource "yandex_dns_recordset" "cdn_cname" {
  count = var.cdn_enabled && local.dns_managed && var.manage_cdn_record ? 1 : 0

  zone_id = local.dns_zone_id
  name    = "${local.cdn_hostname}."
  type    = "CNAME"
  ttl     = var.dns_ttl
  data    = [yandex_cdn_resource.frontend[0].provider_cname]
}
