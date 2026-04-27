# Локальные значения позволяют единообразно формировать имена и SSH-метаданные.
locals {
  network_name = coalesce(var.network_name, "${var.cluster_name}-network")
  subnet_name  = coalesce(var.subnet_name, "${var.cluster_name}-subnet")
  ssh_key_data = trimspace(coalesce(var.ssh_public_key, file(var.ssh_public_key_path)))
  # kubeadm получает стабильный endpoint через NLB; ручное значение оставлено как аварийное переопределение.
  control_plane_endpoint_ip = coalesce(var.control_plane_endpoint_ip, module.load_balancer.api_external_ip)
}

# Модуль сети создаёт VPC и подсеть для будущего кластера.
module "network" {
  source       = "../modules/network"
  network_name = local.network_name
  subnet_name  = local.subnet_name
  zone         = var.yc_zone
  network_cidr = var.network_cidr
}

# Модуль firewall описывает правила внешнего и внутрикластерного доступа.
module "firewall" {
  source                  = "../modules/firewall"
  cluster_name            = var.cluster_name
  network_id              = module.network.network_id
  allowed_ssh_cidrs       = var.allowed_ssh_cidrs
  allowed_api_cidrs       = var.allowed_api_cidrs
  allowed_ingress_cidrs   = var.allowed_ingress_cidrs
  ingress_http_node_port  = var.ingress_http_node_port
  ingress_https_node_port = var.ingress_https_node_port
}

# Модуль compute создаёт control-plane и worker-узлы кластера.
module "compute" {
  source                     = "../modules/compute"
  cluster_name               = var.cluster_name
  zone                       = var.yc_zone
  vm_prefix                  = var.vm_prefix
  domain_suffix              = var.domain_suffix
  subnet_id                  = module.network.subnet_id
  subnet_cidr                = module.network.network_cidr
  security_group_ids         = [module.firewall.security_group_id]
  node_count_cp              = var.node_count_cp
  node_count_worker          = var.node_count_worker
  ssh_user                   = var.ssh_user
  ssh_public_key             = local.ssh_key_data
  platform_id                = var.platform_id
  image_family               = var.image_family
  disk_type                  = var.disk_type
  control_plane_cores        = var.control_plane_cores
  control_plane_memory_gb    = var.control_plane_memory_gb
  control_plane_disk_size_gb = var.control_plane_disk_size_gb
  worker_cores               = var.worker_cores
  worker_memory_gb           = var.worker_memory_gb
  worker_disk_size_gb        = var.worker_disk_size_gb
  enable_nat                 = var.enable_nat
  preemptible                = var.preemptible
  control_plane_endpoint_ip  = var.control_plane_endpoint_ip
}

# Сетевые балансировщики формируют настоящие HA-точки входа для API и ingress.
module "load_balancer" {
  source                  = "../modules/load_balancer"
  cluster_name            = var.cluster_name
  zone                    = var.yc_zone
  region_id               = var.yc_region
  subnet_id               = module.network.subnet_id
  control_planes          = module.compute.control_planes
  workers                 = module.compute.workers
  ingress_http_node_port  = var.ingress_http_node_port
  ingress_https_node_port = var.ingress_https_node_port
}

# Модуль inventory подготавливает inventory для последующего запуска Ansible.
module "inventory" {
  source            = "../modules/inventory"
  control_planes    = module.compute.control_planes
  workers           = module.compute.workers
  ssh_user          = var.ssh_user
  cluster_name      = var.cluster_name
  control_plane_vip = local.control_plane_endpoint_ip
}
