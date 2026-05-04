locals {
  vault_ingress_enabled = trimspace(var.vault_host) != ""

  vault_ingress_values = {
    server = {
      ingress = {
        enabled          = local.vault_ingress_enabled
        ingressClassName = "nginx"
        annotations = local.vault_ingress_enabled ? {
          "cert-manager.io/cluster-issuer"           = var.vault_tls_cluster_issuer
          "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
        } : {}
        hosts = local.vault_ingress_enabled ? [
          {
            host  = var.vault_host
            paths = ["/"]
          }
        ] : []
        tls = local.vault_ingress_enabled ? [
          {
            secretName = "vault-tls"
            hosts      = [var.vault_host]
          }
        ] : []
      }
    }
  }
}

# Namespace создаётся Terraform-кодом, чтобы Vault не зависел от ручного kubectl apply.
resource "kubernetes_namespace" "security" {
  metadata {
    name = var.vault_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "deployment-kit/component"     = "vault"
    }
  }
}

# ServiceAccount нужен Vault для проверки Kubernetes JWT через TokenReview API.
resource "kubernetes_service_account" "vault_auth" {
  metadata {
    name      = "vault-auth"
    namespace = kubernetes_namespace.security.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "vault_auth_delegator" {
  metadata {
    name = "vault-auth-tokenreview"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_auth.metadata[0].name
    namespace = kubernetes_namespace.security.metadata[0].name
  }
}

# Секрет service-account-token нужен следующему Terraform-слою для настройки Kubernetes auth в Vault.
resource "kubernetes_secret" "vault_auth_token" {
  metadata {
    name      = "vault-auth-token"
    namespace = kubernetes_namespace.security.metadata[0].name

    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.vault_auth.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Установка Vault также находится под Terraform, чтобы chart, версия и values были воспроизводимыми.
resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = var.vault_chart_version
  namespace        = kubernetes_namespace.security.metadata[0].name
  create_namespace = false
  # HA Vault до init/unseal не становится Ready, поэтому ожидание готовности выполняется отдельным bootstrap-шагом.
  wait    = false
  timeout = 900
  atomic  = false

  values = [
    file("${path.module}/${var.vault_values_path}"),
    yamlencode(local.vault_ingress_values)
  ]
}
