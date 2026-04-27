# Статические адреса фиксируют внешние точки входа кластера между повторными apply.
resource "yandex_vpc_address" "api" {
  name = "${var.cluster_name}-api-lb-ip"

  external_ipv4_address {
    zone_id = var.zone
  }
}

resource "yandex_vpc_address" "ingress" {
  name = "${var.cluster_name}-ingress-lb-ip"

  external_ipv4_address {
    zone_id = var.zone
  }
}

# Target group Kubernetes API содержит все control-plane узлы.
resource "yandex_lb_target_group" "api" {
  name      = "${var.cluster_name}-api-tg"
  region_id = var.region_id

  dynamic "target" {
    for_each = var.control_planes

    content {
      subnet_id = var.subnet_id
      address   = target.value.ip
    }
  }
}

# Target group ingress содержит worker-узлы, на которых доступны NodePort ingress-nginx.
resource "yandex_lb_target_group" "ingress" {
  name      = "${var.cluster_name}-ingress-tg"
  region_id = var.region_id

  dynamic "target" {
    for_each = var.workers

    content {
      subnet_id = var.subnet_id
      address   = target.value.ip
    }
  }
}

# Балансировщик Kubernetes API даёт kubeadm и kubectl стабильный HA endpoint.
resource "yandex_lb_network_load_balancer" "api" {
  name = "${var.cluster_name}-api-lb"
  type = "external"

  listener {
    name        = "kubernetes-api"
    port        = 6443
    target_port = 6443
    protocol    = "tcp"

    external_address_spec {
      address    = yandex_vpc_address.api.external_ipv4_address[0].address
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.api.id

    healthcheck {
      name                = "kubernetes-api-tcp"
      interval            = 5
      timeout             = 2
      healthy_threshold   = 2
      unhealthy_threshold = 2

      tcp_options {
        port = 6443
      }
    }
  }
}

# Балансировщик ingress публикует стандартные 80/443 и перенаправляет их на NodePort.
resource "yandex_lb_network_load_balancer" "ingress" {
  name = "${var.cluster_name}-ingress-lb"
  type = "external"

  listener {
    name        = "http"
    port        = 80
    target_port = var.ingress_http_node_port
    protocol    = "tcp"

    external_address_spec {
      address    = yandex_vpc_address.ingress.external_ipv4_address[0].address
      ip_version = "ipv4"
    }
  }

  listener {
    name        = "https"
    port        = 443
    target_port = var.ingress_https_node_port
    protocol    = "tcp"

    external_address_spec {
      address    = yandex_vpc_address.ingress.external_ipv4_address[0].address
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.ingress.id

    healthcheck {
      name                = "ingress-http-tcp"
      interval            = 5
      timeout             = 2
      healthy_threshold   = 2
      unhealthy_threshold = 2

      tcp_options {
        port = var.ingress_http_node_port
      }
    }
  }
}

