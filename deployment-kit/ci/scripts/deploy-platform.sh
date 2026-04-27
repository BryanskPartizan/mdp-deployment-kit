#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

CERT_MANAGER_VERSION=${CERT_MANAGER_VERSION:-v1.20.0}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-3.13.0}

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

require_file "$KUBECONFIG"
require_file kubernetes/bootstrap/namespaces.yaml

kubectl apply -f kubernetes/bootstrap/namespaces.yaml
kubectl apply -f kubernetes/bootstrap/local-path-storage.yaml
kubectl apply -f kubernetes/bootstrap/storageclass.yaml
wait_rollout local-path-storage deployment local-path-provisioner

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
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

helm upgrade --install metrics-server oci://registry.k8s.io/metrics-server/metrics-server \
  --version "$METRICS_SERVER_CHART_VERSION" \
  --namespace kube-system \
  --wait \
  --timeout 10m \
  -f kubernetes/base/metrics-server-values.yaml

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  --wait \
  --timeout 15m \
  -f kubernetes/base/prometheus-stack-values.yaml

helm upgrade --install loki grafana/loki \
  --namespace observability \
  --wait \
  --timeout 15m \
  -f kubernetes/base/loki-values.yaml

helm upgrade --install promtail grafana/promtail \
  --namespace observability \
  --wait \
  --timeout 10m \
  -f kubernetes/base/promtail-values.yaml

kubectl get pods -A
kubectl get sc
kubectl get clusterissuer
