#!/usr/bin/env bash
# Скрипт обновляет только Helm charts demo-приложений после сборки образов в GitLab CI.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
NAMESPACE=${APP_NAMESPACE:-app}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-${REGISTRY_SERVER:-registry.${APP_DOMAIN}}}
IMAGE_TAG=${APP_IMAGE_TAG:-${IMAGE_TAG:-${CI_COMMIT_SHORT_SHA:-0.2.0}}}
REGISTRY_SERVER=${REGISTRY_SERVER:-${CI_REGISTRY:-${IMAGE_REGISTRY}}}
REGISTRY_USER=${REGISTRY_USER:-${CI_REGISTRY_USER:-root}}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-${CI_REGISTRY_PASSWORD:-}}
APP_SERVICES=${APP_SERVICES:-api,gateway,frontend}

export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Не найден обязательный файл: $path" >&2; exit 1; }
}

prepare_kubeconfig() {
  if [[ -f "$KUBECONFIG" ]]; then
    return
  fi

  if [[ -z "${KUBECONFIG_B64:-}" ]]; then
    echo "Не найден kubeconfig ${KUBECONFIG}; задайте KUBECONFIG_B64 в GitLab CI variables." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$KUBECONFIG")"
  printf '%s' "$KUBECONFIG_B64" | base64 -d > "$KUBECONFIG"
  chmod 0600 "$KUBECONFIG"
}

validate_tls_issuer() {
  if [[ "$TLS_CLUSTER_ISSUER" == "letsencrypt-staging" ]]; then
    echo "letsencrypt-staging запрещён. Используйте letsencrypt-prod для публичного домена или test-selfsigned для приватного mdp." >&2
    exit 1
  fi
}

create_registry_secret() {
  if [[ -z "$REGISTRY_SERVER" || -z "$REGISTRY_USER" || -z "$REGISTRY_PASSWORD" ]]; then
    echo "Для деплоя приватных образов задайте REGISTRY_SERVER, REGISTRY_USER и REGISTRY_PASSWORD." >&2
    exit 1
  fi

  # Секрет обновляется без удаления, чтобы уже запущенные Pod'ы не теряли ссылку на imagePullSecret.
  kubectl -n "$NAMESPACE" create secret docker-registry gitlab-registry \
    --docker-server="$REGISTRY_SERVER" \
    --docker-username="$REGISTRY_USER" \
    --docker-password="$REGISTRY_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
}

values_suffix() {
  if [[ "$ENV_NAME" == *stage* ]]; then
    echo "stage"
  else
    echo "dev"
  fi
}

deploy_chart() {
  local app="$1"
  local chart_path="kubernetes/apps/${app}"
  local host

  case "$app" in
    api) host="api.${APP_DOMAIN}" ;;
    gateway) host="gateway.${APP_DOMAIN}" ;;
    frontend) host="app.${APP_DOMAIN}" ;;
    *)
      echo "Неизвестное приложение: ${app}" >&2
      exit 1
      ;;
  esac

  require_file "${chart_path}/Chart.yaml"
  require_file "${chart_path}/values.yaml"
  require_file "${chart_path}/values-$(values_suffix).yaml"

  echo "Деплой ${app}: ${IMAGE_REGISTRY}/platform/${app}:${IMAGE_TAG}"
  helm upgrade --install "$app" "$chart_path" \
    --namespace "$NAMESPACE" \
    --wait \
    --timeout 10m \
    -f "${chart_path}/values.yaml" \
    -f "${chart_path}/values-$(values_suffix).yaml" \
    --set-string "image.repository=${IMAGE_REGISTRY}/platform/${app}" \
    --set-string "image.tag=${IMAGE_TAG}" \
    --set-string "ingress.host=${host}" \
    --set-string "ingress.clusterIssuer=${TLS_CLUSTER_ISSUER}"
}

prepare_kubeconfig
require_file "$KUBECONFIG"
validate_tls_issuer

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
create_registry_secret

IFS=',' read -r -a services <<< "$APP_SERVICES"
for app in "${services[@]}"; do
  deploy_chart "$app"
done

for app in "${services[@]}"; do
  kubectl -n "$NAMESPACE" rollout status "deployment/${app}" --timeout=600s
done

kubectl -n "$NAMESPACE" get pods,svc,ingress
