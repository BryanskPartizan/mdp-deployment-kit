# Создание отдельной VPC-сети под Kubernetes-кластер.
resource "yandex_vpc_network" "this" {
  name = var.network_name
}

# Подсеть используется всеми узлами кластера.
resource "yandex_vpc_subnet" "this" {
  name           = var.subnet_name
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.network_cidr]
}
