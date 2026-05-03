#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
NAMESPACE=${APP_NAMESPACE:-app}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_ROOT_SECRET=${GITLAB_ROOT_SECRET:-gitlab-root-password}
ALLOW_INSECURE_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}
ROTATE_POSTGRES_SECRET=${ROTATE_POSTGRES_SECRET:-false}
POSTGRES_CHART_VERSION=${POSTGRES_CHART_VERSION:-18.6.2}
REDIS_CHART_VERSION=${REDIS_CHART_VERSION:-25.4.1}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-${REGISTRY_SERVER:-registry.${APP_DOMAIN}}}
IMAGE_TAG=${APP_IMAGE_TAG:-${IMAGE_TAG:-0.2.0}}

validate_tls_issuer() {
  if [[ "$TLS_CLUSTER_ISSUER" == "letsencrypt-staging" ]]; then
    echo "letsencrypt-staging запрещён. Используйте letsencrypt-prod для публичного домена или test-selfsigned для приватного mdp." >&2
    exit 1
  fi
}

secret_or_demo() {
  local var_name="$1"
  local demo_value="$2"
  local value="${!var_name:-}"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  if [[ "$ALLOW_INSECURE_DEMO_SECRETS" == "true" ]]; then
    printf '%s' "$demo_value"
    return
  fi

  echo "Задайте ${var_name} или включите ALLOW_INSECURE_DEMO_SECRETS=true для demo-стенда." >&2
  exit 1
}

create_registry_secret_if_possible() {
  local registry_server=${REGISTRY_SERVER:-${CI_REGISTRY:-registry.${APP_DOMAIN}}}
  local registry_user=${REGISTRY_USER:-${CI_REGISTRY_USER:-root}}
  local registry_password=${REGISTRY_PASSWORD:-${CI_REGISTRY_PASSWORD:-}}

  if [[ -z "$registry_password" ]] && kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" >/dev/null 2>&1; then
    echo "Пароль registry не задан явно; используем secret ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET}."
    registry_password=$(kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" -o jsonpath='{.data.password}' | base64 --decode)
  fi

  if [[ -z "$registry_server" || -z "$registry_user" || -z "$registry_password" ]]; then
    echo "Не удалось подготовить учетные данные registry. Задайте REGISTRY_SERVER, REGISTRY_USER и REGISTRY_PASSWORD либо убедитесь, что существует ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET}." >&2
    exit 1
  fi

  # Секрет registry обновляется через apply, чтобы kubelet не видел временный разрыв между delete/create.
  kubectl -n "$NAMESPACE" create secret docker-registry gitlab-registry \
    --docker-server="$registry_server" \
    --docker-username="$registry_user" \
    --docker-password="$registry_password" \
    --dry-run=client -o yaml | kubectl apply -f -
}

create_postgres_secret() {
  local pg_user=${POSTGRES_APP_USER:-app}
  local pg_db=${POSTGRES_DB:-appdb}
  local pg_password
  local pg_admin_password

  if kubectl -n "$NAMESPACE" get secret postgres-auth >/dev/null 2>&1; then
    if [[ "$ROTATE_POSTGRES_SECRET" != "true" ]]; then
      echo "Secret ${NAMESPACE}/postgres-auth уже существует; повторное создание пропущено. Для явной ротации задайте ROTATE_POSTGRES_SECRET=true."
      return
    fi
    # Ротация пароля PostgreSQL должна быть осознанной: chart не меняет пароль в уже инициализированной БД автоматически.
    kubectl -n "$NAMESPACE" delete secret postgres-auth >/dev/null
  fi

  pg_password=$(secret_or_demo POSTGRES_APP_PASSWORD "app-demo-password-change-me")
  pg_admin_password=$(secret_or_demo POSTGRES_ADMIN_PASSWORD "postgres-demo-password-change-me")

  kubectl -n "$NAMESPACE" create secret generic postgres-auth \
    --from-literal=postgres-password="$pg_admin_password" \
    --from-literal=password="$pg_password" \
    --from-literal=username="$pg_user" \
    --from-literal=database="$pg_db" \
    --dry-run=client -o yaml | kubectl apply -f -
}

wait_rollout() {
  local ns="$1"
  local kind="$2"
  local name="$3"
  kubectl -n "$ns" rollout status "$kind/$name" --timeout=600s
}

render_app_probes() {
  local output
  output=$(mktemp)
  # Проверки endpoint'ов хранят публичный профиль pkhco.ru, а при deploy подставляется текущий APP_DOMAIN.
  sed \
    -e "s|app\\.pkhco.ru|app.${APP_DOMAIN}|g" \
    -e "s|gateway\\.pkhco.ru|gateway.${APP_DOMAIN}|g" \
    kubernetes/observability/probes/app-probes.yaml > "$output"
  echo "$output"
}

POSTGRES_ENV_FILE=kubernetes/apps/postgres/values-dev.yaml
REDIS_ENV_FILE=kubernetes/apps/redis/values-dev.yaml
APP_ENV_FILE_SUFFIX=dev
if [[ "$ENV_NAME" == *stage* ]]; then
  POSTGRES_ENV_FILE=kubernetes/apps/postgres/values-stage.yaml
  REDIS_ENV_FILE=kubernetes/apps/redis/values-stage.yaml
  APP_ENV_FILE_SUFFIX=stage
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
validate_tls_issuer
create_registry_secret_if_possible
create_postgres_secret

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update bitnami

helm upgrade --install postgres bitnami/postgresql \
  --version "$POSTGRES_CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 15m \
  -f kubernetes/apps/postgres/values.yaml \
  -f "$POSTGRES_ENV_FILE"

helm upgrade --install redis bitnami/redis \
  --version "$REDIS_CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 15m \
  -f kubernetes/apps/redis/values.yaml \
  -f "$REDIS_ENV_FILE"

helm upgrade --install api kubernetes/apps/api \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/api/values.yaml \
  -f "kubernetes/apps/api/values-${APP_ENV_FILE_SUFFIX}.yaml" \
  --set-string "image.repository=${IMAGE_REGISTRY}/platform/api" \
  --set-string "image.tag=${IMAGE_TAG}" \
  --set-string "ingress.host=api.${APP_DOMAIN}" \
  --set-string "ingress.clusterIssuer=${TLS_CLUSTER_ISSUER}"

helm upgrade --install gateway kubernetes/apps/gateway \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/gateway/values.yaml \
  -f "kubernetes/apps/gateway/values-${APP_ENV_FILE_SUFFIX}.yaml" \
  --set-string "image.repository=${IMAGE_REGISTRY}/platform/gateway" \
  --set-string "image.tag=${IMAGE_TAG}" \
  --set-string "ingress.host=gateway.${APP_DOMAIN}" \
  --set-string "ingress.clusterIssuer=${TLS_CLUSTER_ISSUER}"

helm upgrade --install frontend kubernetes/apps/frontend \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/frontend/values.yaml \
  -f "kubernetes/apps/frontend/values-${APP_ENV_FILE_SUFFIX}.yaml" \
  --set-string "image.repository=${IMAGE_REGISTRY}/platform/frontend" \
  --set-string "image.tag=${IMAGE_TAG}" \
  --set-string "ingress.host=app.${APP_DOMAIN}" \
  --set-string "ingress.clusterIssuer=${TLS_CLUSTER_ISSUER}"

kubectl apply -f kubernetes/security/rbac/
kubectl apply -f kubernetes/security/network-policies/
kubectl apply -f kubernetes/backup/

wait_rollout "$NAMESPACE" statefulset postgres-postgresql
wait_rollout "$NAMESPACE" statefulset redis-master
wait_rollout "$NAMESPACE" deployment api
wait_rollout "$NAMESPACE" deployment gateway
wait_rollout "$NAMESPACE" deployment frontend

APP_PROBES_FILE=$(render_app_probes)
trap 'rm -f "$APP_PROBES_FILE"' EXIT
kubectl apply -f "$APP_PROBES_FILE"

kubectl -n "$NAMESPACE" get pods,svc,ingress
