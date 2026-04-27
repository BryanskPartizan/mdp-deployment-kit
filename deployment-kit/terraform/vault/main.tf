# KV v2 хранит прикладные секреты, которые затем выдаются через Kubernetes auth.
resource "vault_mount" "app_kv" {
  path        = var.kv_mount_path
  type        = "kv-v2"
  description = "KV v2 хранилище секретов прикладного контура deployment-kit."
}

# Kubernetes auth позволяет Pod'ам получать секреты по своему ServiceAccount JWT.
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = file(var.kubernetes_ca_cert_path)
  token_reviewer_jwt = var.token_reviewer_jwt
}

locals {
  # Описываем роли компактно, чтобы новые приложения добавлялись одной записью.
  apps = {
    api = {
      service_account = "api"
      secret_path     = "app/api"
      demo_secret = {
        DATABASE_URL = "postgresql://app:app-password@postgres-postgresql.${var.app_namespace}.svc.cluster.local:5432/appdb"
        REDIS_URL    = "redis://redis-master.${var.app_namespace}.svc.cluster.local:6379"
      }
    }
    gateway = {
      service_account = "gateway"
      secret_path     = "app/gateway"
      demo_secret = {
        API_BASE_URL = "http://api.${var.app_namespace}.svc.cluster.local:8081"
      }
    }
    frontend = {
      service_account = "frontend"
      secret_path     = "app/frontend"
      demo_secret = {
        GATEWAY_BASE_URL = "http://gateway.${var.app_namespace}.svc.cluster.local:8080"
      }
    }
  }
}

resource "vault_policy" "app" {
  for_each = local.apps

  name = "app-${each.key}"

  policy = <<-EOT
    path "${var.kv_mount_path}/data/${each.value.secret_path}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "app" {
  for_each = local.apps

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_names      = [each.value.service_account]
  bound_service_account_namespaces = [var.app_namespace]
  token_policies                   = [vault_policy.app[each.key].name]
  token_ttl                        = 3600
}

# Демонстрационные секреты нужны для smoke-проверки связки Vault -> Pod.
# Реальные значения должны передаваться через защищённый tfvars/CI variables.
resource "vault_kv_secret_v2" "app_demo" {
  for_each = local.apps

  mount     = vault_mount.app_kv.path
  name      = each.value.secret_path
  data_json = jsonencode(each.value.demo_secret)
}

