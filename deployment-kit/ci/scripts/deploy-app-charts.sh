#!/usr/bin/env bash
# Скрипт обновляет только Helm charts demo-приложений после сборки образов в GitLab CI.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NAMESPACE=${APP_NAMESPACE:-app}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_ROOT_SECRET=${GITLAB_ROOT_SECRET:-gitlab-root-password}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-${REGISTRY_SERVER:-registry.${APP_DOMAIN}}}
IMAGE_TAG=${APP_IMAGE_TAG:-${IMAGE_TAG:-${CI_COMMIT_SHORT_SHA:-0.2.0}}}
REGISTRY_SERVER=${REGISTRY_SERVER:-${CI_REGISTRY:-${IMAGE_REGISTRY}}}
REGISTRY_USER=${REGISTRY_USER:-${CI_REGISTRY_USER:-root}}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-${CI_REGISTRY_PASSWORD:-}}
APP_SERVICES=${APP_SERVICES:-api,gateway,frontend}

export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

source "${SCRIPT_DIR}/lib/public-tls.sh"

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
  validate_public_tls_inputs
}

is_placeholder() {
  [[ "${1:-}" == REPLACE_WITH_* ]]
}

create_registry_secret() {
  if is_placeholder "$REGISTRY_USER"; then
    REGISTRY_USER=root
  fi

  if is_placeholder "$REGISTRY_PASSWORD"; then
    REGISTRY_PASSWORD=""
  fi

  if [[ -z "$REGISTRY_PASSWORD" ]] && kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" >/dev/null 2>&1; then
    echo "Пароль registry не задан явно; используем secret ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET}."
    REGISTRY_PASSWORD=$(kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" -o jsonpath='{.data.password}' | base64 --decode)
  fi

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

check_app_images_if_possible() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Проверка наличия app-образов пропущена: docker CLI недоступен."
    return 0
  fi

  local image
  IFS=',' read -r -a services_to_check <<< "$APP_SERVICES"
  for app in "${services_to_check[@]}"; do
    image="${IMAGE_REGISTRY}/platform/${app}:${IMAGE_TAG}"
    echo "Проверка наличия образа ${image}."
    if ! docker manifest inspect "$image" >/dev/null 2>&1; then
      echo "Образ ${image} не найден или недоступен. Сначала выполните сборку и push образов." >&2
      exit 1
    fi
  done
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
    --hide-notes \
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
require_prod_cluster_issuer

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
create_registry_secret
check_app_images_if_possible
delete_tls_artifact_if_not_prod "$NAMESPACE" api-tls api-tls
delete_tls_artifact_if_not_prod "$NAMESPACE" gateway-tls gateway-tls
delete_tls_artifact_if_not_prod "$NAMESPACE" frontend-tls frontend-tls

IFS=',' read -r -a services <<< "$APP_SERVICES"
for app in "${services[@]}"; do
  deploy_chart "$app"
done

for app in "${services[@]}"; do
  kubectl -n "$NAMESPACE" rollout status "deployment/${app}" --timeout=600s
done

if [[ ",${APP_SERVICES}," == *",gateway,"* ]]; then
  wait_certificate_ready "$NAMESPACE" gateway-tls 1200s
fi
if [[ ",${APP_SERVICES}," == *",frontend,"* ]]; then
  wait_certificate_ready "$NAMESPACE" frontend-tls 1200s
fi
if [[ ",${APP_SERVICES}," == *",api,"* ]] && kubectl -n "$NAMESPACE" get certificate api-tls >/dev/null 2>&1; then
  wait_certificate_ready "$NAMESPACE" api-tls 1200s
fi

kubectl -n "$NAMESPACE" get pods,svc,ingress
