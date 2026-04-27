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
    description    = "Доступ к Kubernetes API"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description    = "Входящий HTTP-трафик"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = var.allowed_ingress_cidrs
  }

  ingress {
    description    = "Входящий HTTPS-трафик"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = var.allowed_ingress_cidrs
  }

  ingress {
    description       = "Внутрикластерный трафик"
    protocol          = "ANY"
    predefined_target = "self_security_group"
  }

  egress {
    description    = "Разрешить весь исходящий трафик"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
