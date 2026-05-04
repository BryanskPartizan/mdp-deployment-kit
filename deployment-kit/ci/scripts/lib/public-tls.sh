#!/usr/bin/env bash
# Общие guardrails публичного TLS-профиля deployment-kit.

validate_public_tls_inputs() {
  if [[ "${TLS_CLUSTER_ISSUER:-}" != "letsencrypt-prod" ]]; then
    echo "TLS_CLUSTER_ISSUER должен быть letsencrypt-prod. Self-signed и staging режимы для публичного стенда запрещены." >&2
    exit 1
  fi

  if [[ "${APP_DOMAIN:-}" == "mdp" || "${APP_DOMAIN:-}" != *.* ]]; then
    echo "APP_DOMAIN должен быть публичным доменом, например pkhco.ru. Приватный mdp запрещён для публичного TLS." >&2
    exit 1
  fi
}

require_prod_cluster_issuer() {
  if ! kubectl get clusterissuer letsencrypt-prod >/dev/null 2>&1; then
    echo "ClusterIssuer letsencrypt-prod не найден. Сначала выполните make deploy-platform ENV=<env> с LETSENCRYPT_EMAIL." >&2
    exit 1
  fi
}

delete_non_prod_cluster_issuers() {
  if ! kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
    echo "CRD ClusterIssuer ещё не установлена; удаление non-prod issuers пропущено."
    return
  fi

  # Non-prod issuers удаляются, чтобы новые ingress не могли случайно получить непубличный TLS.
  kubectl delete clusterissuer letsencrypt-staging test-selfsigned selfsigned-bootstrap --ignore-not-found
}

delete_tls_artifact_if_not_prod() {
  local namespace="$1"
  local certificate="$2"
  local secret="$3"
  local issuer=""
  local secret_exists=false

  issuer=$(kubectl -n "$namespace" get certificate "$certificate" -o jsonpath='{.spec.issuerRef.name}' 2>/dev/null || true)
  if kubectl -n "$namespace" get secret "$secret" >/dev/null 2>&1; then
    secret_exists=true
  fi

  if [[ -n "$issuer" && "$issuer" != "letsencrypt-prod" ]]; then
    echo "Удаляем non-prod TLS artifact ${namespace}/${certificate} и secret ${secret}; будет перевыпущен через letsencrypt-prod."
    kubectl -n "$namespace" delete certificate "$certificate" --ignore-not-found
    kubectl -n "$namespace" delete secret "$secret" --ignore-not-found
    return
  fi

  if [[ -z "$issuer" && "$secret_exists" == "true" ]]; then
    echo "Удаляем TLS secret ${namespace}/${secret} без Certificate; cert-manager пересоздаст его через letsencrypt-prod."
    kubectl -n "$namespace" delete secret "$secret" --ignore-not-found
  fi
}

wait_certificate_ready() {
  local namespace="$1"
  local certificate="$2"
  local timeout="${3:-900s}"

  echo "Ожидание TLS certificate ${namespace}/${certificate}."
  if kubectl -n "$namespace" wait --for=condition=Ready "certificate/${certificate}" --timeout="$timeout"; then
    return 0
  fi

  echo "Certificate ${namespace}/${certificate} не стал Ready за ${timeout}. Диагностика cert-manager:" >&2
  kubectl -n "$namespace" get certificate,certificaterequest,order,challenge -o wide >&2 || true
  kubectl -n "$namespace" describe certificate "$certificate" >&2 || true
  return 1
}
