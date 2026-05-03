#!/usr/bin/env bash
# Скрипт разворачивает GitLab как devops-компонент платформы через официальный Helm chart.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_RELEASE=${GITLAB_RELEASE:-gitlab}
GITLAB_CHART_VERSION=${GITLAB_CHART_VERSION:-9.11.1}
GITLAB_ROOT_SECRET=${GITLAB_ROOT_SECRET:-gitlab-root-password}
ALLOW_INSECURE_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}
ROTATE_GITLAB_ROOT_PASSWORD=${ROTATE_GITLAB_ROOT_PASSWORD:-false}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Не найден обязательный файл: $path" >&2; exit 1; }
}

validate_tls_issuer() {
  if [[ "$TLS_CLUSTER_ISSUER" == "letsencrypt-staging" ]]; then
    echo "letsencrypt-staging запрещён. Используйте letsencrypt-prod для публичного домена или test-selfsigned для приватного mdp." >&2
    exit 1
  fi
}

generate_demo_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32
  else
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d '\n'
    echo
  fi
}

resolve_gitlab_root_password() {
  local password_file="${ARTIFACTS_DIR}/gitlab-root-password"

  if [[ -n "${GITLAB_ROOT_PASSWORD:-}" ]]; then
    printf '%s' "$GITLAB_ROOT_PASSWORD"
    return
  fi

  if kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" >/dev/null 2>&1; then
    kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" -o jsonpath='{.data.password}' | base64 --decode
    return
  fi

  if [[ "$ALLOW_INSECURE_DEMO_SECRETS" == "true" ]]; then
    mkdir -p "$ARTIFACTS_DIR"
    if [[ ! -f "$password_file" ]]; then
      generate_demo_password > "$password_file"
      chmod 0600 "$password_file"
    fi
    cat "$password_file"
    return
  fi

  echo "Задайте GITLAB_ROOT_PASSWORD или включите ALLOW_INSECURE_DEMO_SECRETS=true для demo-стенда." >&2
  exit 1
}

values_for_env() {
  if [[ "$ENV_NAME" == *stage* ]]; then
    echo "kubernetes/platform/gitlab/values-stage.yaml"
  else
    echo "kubernetes/platform/gitlab/values-dev.yaml"
  fi
}

resolve_ingress_ip() {
  local outputs="${ARTIFACTS_DIR}/terraform-outputs.json"

  if [[ -f "$outputs" ]] && command -v jq >/dev/null 2>&1; then
    jq -r '.ingress_external_ip.value // empty' "$outputs"
  fi
}

render_gitlab_probes() {
  local output
  output=$(mktemp)
  # Проверки endpoint'ов хранят публичный профиль pkhco.ru, а при deploy подставляется текущий APP_DOMAIN.
  sed \
    -e "s|gitlab\\.pkhco.ru|gitlab.${APP_DOMAIN}|g" \
    -e "s|registry\\.pkhco.ru|registry.${APP_DOMAIN}|g" \
    kubernetes/observability/probes/gitlab-probes.yaml > "$output"
  echo "$output"
}

render_gitlab_domain_values() {
  local output
  output=$(mktemp)
  # Ключ annotation содержит точку и slash, поэтому надёжнее передавать его values-файлом, а не helm --set.
  cat > "$output" <<EOF
global:
  hosts:
    domain: ${APP_DOMAIN}
    gitlab:
      name: gitlab.${APP_DOMAIN}
    registry:
      name: registry.${APP_DOMAIN}
    minio:
      name: minio.${APP_DOMAIN}
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: ${TLS_CLUSTER_ISSUER}
EOF
  echo "$output"
}

ensure_gitlab_root_secret() {
  local password="$1"

  if kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" >/dev/null 2>&1; then
    if [[ "$ROTATE_GITLAB_ROOT_PASSWORD" != "true" ]]; then
      echo "Secret ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET} уже существует; повторное создание пропущено. Для явной ротации задайте ROTATE_GITLAB_ROOT_PASSWORD=true."
      return
    fi
    # Root password GitLab нельзя неявно пересоздавать: это может разойтись с состоянием БД.
    kubectl -n "$GITLAB_NAMESPACE" delete secret "$GITLAB_ROOT_SECRET" >/dev/null
  fi

  kubectl -n "$GITLAB_NAMESPACE" create secret generic "$GITLAB_ROOT_SECRET" \
    --from-literal=password="$password" \
    --dry-run=client -o yaml | kubectl apply -f -
}

require_file "$KUBECONFIG"
validate_tls_issuer
require_file kubernetes/platform/gitlab/values.yaml
require_file kubernetes/observability/probes/gitlab-probes.yaml

kubectl create namespace "$GITLAB_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ci --dry-run=client -o yaml | kubectl apply -f -

ROOT_PASSWORD=$(resolve_gitlab_root_password)
ensure_gitlab_root_secret "$ROOT_PASSWORD"

EXTERNAL_IP=$(resolve_ingress_ip)
HELM_SET_ARGS=()
if [[ -n "$EXTERNAL_IP" ]]; then
  HELM_SET_ARGS+=(--set-string "global.hosts.externalIP=${EXTERNAL_IP}")
fi
GITLAB_DOMAIN_VALUES_FILE=$(render_gitlab_domain_values)
trap 'rm -f "$GITLAB_DOMAIN_VALUES_FILE"' EXIT

helm repo add gitlab https://charts.gitlab.io >/dev/null 2>&1 || true
helm repo update gitlab

helm upgrade --install "$GITLAB_RELEASE" gitlab/gitlab \
  --version "$GITLAB_CHART_VERSION" \
  --namespace "$GITLAB_NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 45m \
  -f kubernetes/platform/gitlab/values.yaml \
  -f "$(values_for_env)" \
  -f "$GITLAB_DOMAIN_VALUES_FILE" \
  "${HELM_SET_ARGS[@]}"

GITLAB_PROBES_FILE=$(render_gitlab_probes)
trap 'rm -f "$GITLAB_DOMAIN_VALUES_FILE" "$GITLAB_PROBES_FILE"' EXIT
kubectl apply -f "$GITLAB_PROBES_FILE"

kubectl -n "$GITLAB_NAMESPACE" get pods,svc,ingress,pvc
echo "GitLab root password хранится в Kubernetes secret ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET}."
