#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
NAMESPACE=${APP_NAMESPACE:-app}

create_registry_secret_if_possible() {
  if [[ -n "${CI_REGISTRY:-}" && -n "${CI_REGISTRY_USER:-}" && -n "${CI_REGISTRY_PASSWORD:-}" ]]; then
    kubectl -n "$NAMESPACE" delete secret gitlab-registry --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "$NAMESPACE" create secret docker-registry gitlab-registry \
      --docker-server="$CI_REGISTRY" \
      --docker-username="$CI_REGISTRY_USER" \
      --docker-password="$CI_REGISTRY_PASSWORD"
  else
    echo "Учетные данные CI-реестра не заданы; предполагается, что secret gitlab-registry уже существует либо используются публичные образы."
  fi
}

create_postgres_secret() {
  local pg_user=${POSTGRES_APP_USER:-app}
  local pg_db=${POSTGRES_DB:-appdb}
  local pg_password=${POSTGRES_APP_PASSWORD:-app-password}
  local pg_admin_password=${POSTGRES_ADMIN_PASSWORD:-postgres-password}

  kubectl -n "$NAMESPACE" delete secret postgres-auth --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" create secret generic postgres-auth \
    --from-literal=postgres-password="$pg_admin_password" \
    --from-literal=password="$pg_password" \
    --from-literal=username="$pg_user" \
    --from-literal=database="$pg_db"
}

wait_rollout() {
  local ns="$1"
  local kind="$2"
  local name="$3"
  kubectl -n "$ns" rollout status "$kind/$name" --timeout=600s
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

helm upgrade --install postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 15m \
  -f kubernetes/apps/postgres/values.yaml \
  -f "$POSTGRES_ENV_FILE"

helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis \
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
  -f "kubernetes/apps/api/values-${APP_ENV_FILE_SUFFIX}.yaml"

helm upgrade --install gateway kubernetes/apps/gateway \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/gateway/values.yaml \
  -f "kubernetes/apps/gateway/values-${APP_ENV_FILE_SUFFIX}.yaml"

helm upgrade --install frontend kubernetes/apps/frontend \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  -f kubernetes/apps/frontend/values.yaml \
  -f "kubernetes/apps/frontend/values-${APP_ENV_FILE_SUFFIX}.yaml"

kubectl apply -f kubernetes/security/rbac/
kubectl apply -f kubernetes/security/network-policies/
kubectl apply -f kubernetes/backup/

wait_rollout "$NAMESPACE" statefulset postgres-postgresql
wait_rollout "$NAMESPACE" statefulset redis-master
wait_rollout "$NAMESPACE" deployment api
wait_rollout "$NAMESPACE" deployment gateway
wait_rollout "$NAMESPACE" deployment frontend

kubectl -n "$NAMESPACE" get pods,svc,ingress
