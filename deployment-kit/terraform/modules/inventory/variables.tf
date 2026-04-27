variable "control_planes" {
  type = list(object({
    name         = string
    ip           = string
    ansible_host = string
    fqdn         = string
  }))
}

variable "workers" {
  type = list(object({
    name         = string
    ip           = string
    ansible_host = string
    fqdn         = string
  }))
}

variable "ssh_user" { type = string }
variable "cluster_name" { type = string }
variable "control_plane_vip" { type = string }
