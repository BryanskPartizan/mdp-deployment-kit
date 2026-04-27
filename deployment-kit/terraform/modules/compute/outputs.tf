output "control_planes" {
  description = "Управляющие узлы с внутренними и внешними адресами."
  value = [
    for name in sort(keys(yandex_compute_instance.control_plane)) : {
      name        = yandex_compute_instance.control_plane[name].name
      ip          = yandex_compute_instance.control_plane[name].network_interface[0].ip_address
      ansible_host = try(yandex_compute_instance.control_plane[name].network_interface[0].nat_ip_address, yandex_compute_instance.control_plane[name].network_interface[0].ip_address)
      fqdn        = yandex_compute_instance.control_plane[name].fqdn
    }
  ]
}

output "workers" {
  description = "Worker-узлы с внутренними и внешними адресами."
  value = [
    for name in sort(keys(yandex_compute_instance.worker)) : {
      name        = yandex_compute_instance.worker[name].name
      ip          = yandex_compute_instance.worker[name].network_interface[0].ip_address
      ansible_host = try(yandex_compute_instance.worker[name].network_interface[0].nat_ip_address, yandex_compute_instance.worker[name].network_interface[0].ip_address)
      fqdn        = yandex_compute_instance.worker[name].fqdn
    }
  ]
}

output "all_nodes" {
  description = "Все автоматически созданные узлы."
  value = concat(
    [for name in sort(keys(yandex_compute_instance.control_plane)) : yandex_compute_instance.control_plane[name].name],
    [for name in sort(keys(yandex_compute_instance.worker)) : yandex_compute_instance.worker[name].name]
  )
}

output "control_plane_vip" {
  description = "Endpoint used by kubeadm controlPlaneEndpoint."
  value       = local.control_plane_vip
}
