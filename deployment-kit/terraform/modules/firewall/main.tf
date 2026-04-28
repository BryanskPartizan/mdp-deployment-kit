# Единая группа безопасности назначается всем узлам кластера.
resource "yandex_vpc_security_group" "this" {
  name       = "${var.cluster_name}-k8s-sg"
  network_id = var.network_id

  ingress {
    description    = "Доступ по SSH"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description    = "Доступ к Kubernetes API через внешний HA endpoint"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = var.allowed_api_cidrs
  }

  ingress {
    description    = "HTTP-трафик от внешнего NLB к NodePort ingress-nginx"
    protocol       = "TCP"
    port           = var.ingress_http_node_port
    v4_cidr_blocks = var.allowed_ingress_cidrs
  }

  ingress {
    description    = "HTTPS-трафик от внешнего NLB к NodePort ingress-nginx"
    protocol       = "TCP"
    port           = var.ingress_https_node_port
    v4_cidr_blocks = var.allowed_ingress_cidrs
  }

  ingress {
    description       = "Проверки доступности от Yandex Network Load Balancer"
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    description       = "Внутрикластерный трафик"
    protocol          = "ANY"
    predefined_target = "self_security_group"
  }

  egress {
    description    = "Исходящий трафик узлов для bootstrap, registry, package repos и внешних API"
    protocol       = "ANY"
    v4_cidr_blocks = var.allowed_egress_cidrs
  }
}
