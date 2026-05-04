variable "cluster_name" { type = string }
variable "zone" { type = string }
variable "vm_prefix" { type = string }
variable "domain_suffix" { type = string }
variable "subnet_id" { type = string }
variable "subnet_cidr" { type = string }
variable "security_group_ids" { type = list(string) }
variable "node_count_cp" { type = number }
variable "node_count_worker" { type = number }
variable "ssh_user" { type = string }
variable "ssh_public_key" { type = string }
variable "platform_id" { type = string }
variable "image_family" { type = string }
variable "disk_type" { type = string }
variable "control_plane_cores" { type = number }
variable "control_plane_memory_gb" { type = number }
variable "control_plane_disk_size_gb" { type = number }
variable "worker_cores" { type = number }
variable "worker_memory_gb" { type = number }
variable "worker_disk_size_gb" { type = number }
variable "enable_control_plane_nat" { type = bool }
variable "enable_worker_nat" { type = bool }
variable "control_plane_preemptible" { type = bool }
variable "worker_preemptible" { type = bool }
variable "control_plane_endpoint_ip" {
  type    = string
  default = null
}
