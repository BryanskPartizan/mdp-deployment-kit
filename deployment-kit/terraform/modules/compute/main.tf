# Базовый образ выбирается по семейству, что упрощает обновление шаблона VM.
data "yandex_compute_image" "base" {
  family = var.image_family
}

# Локальные структуры позволяют единообразно сформировать список control-plane и worker-узлов.
locals {
  control_plane_defs = {
    for idx in range(var.node_count_cp) : format("%s-cp-%02d", var.vm_prefix, idx + 1) => {
      ip = cidrhost(var.subnet_cidr, 10 + idx)
    }
  }

  worker_defs = {
    for idx in range(var.node_count_worker) : format("%s-worker-%02d", var.vm_prefix, idx + 1) => {
      ip = cidrhost(var.subnet_cidr, 20 + idx)
    }
  }

  first_control_plane_name = sort(keys(local.control_plane_defs))[0]
  control_plane_vip        = coalesce(var.control_plane_endpoint_ip, local.control_plane_defs[local.first_control_plane_name].ip)
}

# Управляющие узлы размещают компоненты control plane и etcd.
resource "yandex_compute_instance" "control_plane" {
  for_each                  = local.control_plane_defs
  name                      = each.key
  hostname                  = each.key
  platform_id               = var.platform_id
  zone                      = var.zone
  allow_stopping_for_update = true

  labels = {
    cluster = var.cluster_name
    role    = "control-plane"
  }

  resources {
    cores  = var.control_plane_cores
    memory = var.control_plane_memory_gb
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      type     = var.disk_type
      size     = var.control_plane_disk_size_gb
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    ip_address         = each.value.ip
    nat                = var.enable_nat
    security_group_ids = var.security_group_ids
  }

  metadata = {
    ssh-keys           = "${var.ssh_user}:${trimspace(var.ssh_public_key)}"
    serial-port-enable = "1"
  }
}

# Worker-узлы предназначены для выполнения прикладных и платформенных нагрузок.
resource "yandex_compute_instance" "worker" {
  for_each                  = local.worker_defs
  name                      = each.key
  hostname                  = each.key
  platform_id               = var.platform_id
  zone                      = var.zone
  allow_stopping_for_update = true

  labels = {
    cluster = var.cluster_name
    role    = "worker"
  }

  resources {
    cores  = var.worker_cores
    memory = var.worker_memory_gb
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      type     = var.disk_type
      size     = var.worker_disk_size_gb
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    ip_address         = each.value.ip
    nat                = var.enable_nat
    security_group_ids = var.security_group_ids
  }

  metadata = {
    ssh-keys           = "${var.ssh_user}:${trimspace(var.ssh_public_key)}"
    serial-port-enable = "1"
  }
}
