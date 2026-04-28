#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
NAMESPACE=${APP_NAMESPACE:-app}
ALLOW_INSECURE_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}
ROTATE_POSTGRES_SECRET=${ROTATE_POSTGRES_SECRET:-false}
POSTGRES_CHART_VERSION=${POSTGRES_CHART_VERSION:-18.6.2}
REDIS_CHART_VERSION=${REDIS_CHART_VERSION:-25.4.1}
APP_DOMAIN=${APP_DOMAIN:-mdp}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-test-selfsigned}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-${REGISTRY_SERVER:-registry.${APP_DOMAIN}}}

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
  local registry_user=${REGISTRY_USER:-${CI_REGISTRY_USER:-}}
  local registry_password=${REGISTRY_PASSWORD:-${CI_REGISTRY_PASSWORD:-}}

  if [[ -n "$registry_server" && -n "$registry_user" && -n "$registry_password" ]]; then
    # Registry secret можно обновлять без удаления: так kubelet не видит временный разрыв.
    kubectl -n "$NAMESPACE" create secret docker-registry gitlab-registry \
      --docker-server="$registry_server" \
      --docker-username="$registry_user" \
      --docker-password="$registry_password" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    echo "Учетные данные реестра не заданы; предполагается, что secret gitlab-registry уже существует либо используются публичные образы."
  fi
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
  # Probes хранят mdp как безопасный дефолт, а при deploy подставляется текущий APP_DOMAIN.
  sed \
    -e "s|app\\.mdp|app.${APP_DOMAIN}|g" \
    -e "s|gateway\\.mdp|gateway.${APP_DOMAIN}|g" \
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
  --set-string "ingress.host=api.${APP_DOMAIN}" \
  --set-string "ingress.clusterIssuer=${TLS_CLUSTER_ISSUER}"

helm upgrade --install gateway kubernetes/apps/gateway \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/gateway/values.yaml \
  -f "kubernetes/apps/gateway/values-${APP_ENV_FILE_SUFFIX}.yaml" \
  --set-string "image.repository=${IMAGE_REGISTRY}/platform/gateway" \
  --set-string "ingress.host=gateway.${APP_DOMAIN}" \
  --set-string "ingress.clusterIssuer=${TLS_CLUSTER_ISSUER}"

helm upgrade --install frontend kubernetes/apps/frontend \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/frontend/values.yaml \
  -f "kubernetes/apps/frontend/values-${APP_ENV_FILE_SUFFIX}.yaml" \
  --set-string "image.repository=${IMAGE_REGISTRY}/platform/frontend" \
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
