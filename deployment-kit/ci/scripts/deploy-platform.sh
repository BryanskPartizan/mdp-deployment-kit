#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

INGRESS_NGINX_CHART_VERSION=${INGRESS_NGINX_CHART_VERSION:-4.15.1}
CERT_MANAGER_VERSION=${CERT_MANAGER_VERSION:-v1.20.2}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-3.13.0}
PROMETHEUS_STACK_CHART_VERSION=${PROMETHEUS_STACK_CHART_VERSION:-84.3.0}
LOKI_CHART_VERSION=${LOKI_CHART_VERSION:-7.0.0}
PROMTAIL_CHART_VERSION=${PROMTAIL_CHART_VERSION:-6.17.1}
ALLOW_INSECURE_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Не найден обязательный файл: $path" >&2; exit 1; }
}

wait_rollout() {
  local ns="$1"
  local kind="$2"
  local name="$3"
  kubectl -n "$ns" rollout status "$kind/$name" --timeout=600s
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

create_grafana_secret() {
  local password
  password=$(secret_or_demo GRAFANA_ADMIN_PASSWORD "admin-demo-password-change-me")

  kubectl -n observability delete secret grafana-admin --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n observability create secret generic grafana-admin \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER:-admin}" \
    --from-literal=admin-password="$password"
}

require_file "$KUBECONFIG"
require_file kubernetes/bootstrap/namespaces.yaml

kubectl apply -f kubernetes/bootstrap/namespaces.yaml
kubectl apply -f kubernetes/bootstrap/local-path-storage.yaml
kubectl apply -f kubernetes/bootstrap/storageclass.yaml
wait_rollout local-path-storage deployment local-path-provisioner
create_grafana_secret

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "$INGRESS_NGINX_CHART_VERSION" \
  --namespace ingress-nginx \
  --create-namespace \
  --wait \
  --timeout 10m \
  -f kubernetes/base/ingress-nginx-values.yaml

helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version "$CERT_MANAGER_VERSION" \
  --namespace cert-manager \
  --create-namespace \
  --wait \
  --timeout 10m \
  -f kubernetes/base/cert-manager-values.yaml

kubectl apply -f kubernetes/bootstrap/cluster-issuers.yaml
kubectl wait --for=condition=Ready clusterissuer/selfsigned-bootstrap --timeout=300s
kubectl wait --for=condition=Ready clusterissuer/test-selfsigned --timeout=300s

helm upgrade --install metrics-server metrics-server/metrics-server \
  --version "$METRICS_SERVER_CHART_VERSION" \
  --namespace kube-system \
  --wait \
  --timeout 10m \
  -f kubernetes/base/metrics-server-values.yaml

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "$PROMETHEUS_STACK_CHART_VERSION" \
  --namespace observability \
  --create-namespace \
  --wait \
  --timeout 15m \
  -f kubernetes/base/prometheus-stack-values.yaml

helm upgrade --install loki grafana/loki \
  --version "$LOKI_CHART_VERSION" \
  --namespace observability \
  --wait \
  --timeout 15m \
  -f kubernetes/base/loki-values.yaml

helm upgrade --install promtail grafana/promtail \
  --version "$PROMTAIL_CHART_VERSION" \
  --namespace observability \
  --wait \
  --timeout 10m \
  -f kubernetes/base/promtail-values.yaml

kubectl get pods -A
kubectl get sc
kubectl get clusterissuer
