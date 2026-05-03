# Inventory формируется на основе Terraform outputs и используется следующей стадией автоматизации.
locals {
  primary_control_plane    = var.control_planes[0]
  secondary_control_planes = length(var.control_planes) > 1 ? slice(var.control_planes, 1, length(var.control_planes)) : []
  # Эти SSH-настройки попадают в generated inventory и делают ручные ansible-команды воспроизводимыми.
  ansible_vars = merge(
    {
      ansible_user            = var.ssh_user
      cluster_name            = var.cluster_name
      control_plane_vip       = var.control_plane_vip
      control_plane_endpoint  = "${var.control_plane_vip}:6443"
      ansible_ssh_common_args = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    },
    var.ssh_private_key_path != null ? {
      ansible_ssh_private_key_file = var.ssh_private_key_path
    } : {}
  )

  inventory = {
    all = {
      vars = local.ansible_vars
      children = {
        control_plane = {
          hosts = {
            for node in var.control_planes : node.name => {
              ansible_host = node.ansible_host
              node_ip      = node.ip
              fqdn         = node.fqdn
            }
          }
        }
        control_plane_primary = {
          hosts = {
            (local.primary_control_plane.name) = {
              ansible_host = local.primary_control_plane.ansible_host
              node_ip      = local.primary_control_plane.ip
              fqdn         = local.primary_control_plane.fqdn
            }
          }
        }
        control_plane_secondary = {
          hosts = {
            for node in local.secondary_control_planes : node.name => {
              ansible_host = node.ansible_host
              node_ip      = node.ip
              fqdn         = node.fqdn
            }
          }
        }
        workers = {
          hosts = {
            for node in var.workers : node.name => {
              ansible_host = node.ansible_host
              node_ip      = node.ip
              fqdn         = node.fqdn
            }
          }
        }
        kube_cluster = {
          children = {
            control_plane = {}
            workers       = {}
          }
        }
      }
    }
  }
}

# На выходе возвращается YAML-инвентарь, готовый для ansible-playbook.
output "inventory_yaml" {
  value = yamlencode(local.inventory)
}
