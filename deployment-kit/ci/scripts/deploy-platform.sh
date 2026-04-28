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
BLACKBOX_EXPORTER_CHART_VERSION=${BLACKBOX_EXPORTER_CHART_VERSION:-11.9.1}
LOKI_CHART_VERSION=${LOKI_CHART_VERSION:-7.0.0}
ALLOY_CHART_VERSION=${ALLOY_CHART_VERSION:-1.8.0}
ALLOW_INSECURE_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-test-selfsigned}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}

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

apply_public_acme_issuer_if_requested() {
  local issuer="$TLS_CLUSTER_ISSUER"
  local server

  if [[ "$issuer" != "letsencrypt-staging" && "$issuer" != "letsencrypt-prod" ]]; then
    return
  fi

  if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    echo "Для TLS_CLUSTER_ISSUER=${issuer} задайте LETSENCRYPT_EMAIL. Для приватного домена mdp используйте test-selfsigned." >&2
    exit 1
  fi

  if [[ "$issuer" == "letsencrypt-staging" ]]; then
    server="https://acme-staging-v02.api.letsencrypt.org/directory"
  else
    server="https://acme-v02.api.letsencrypt.org/directory"
  fi

  # HTTP-01 solver работает только для публичных доменов, которые уже смотрят на ingress NLB.
  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${issuer}
spec:
  acme:
    email: ${LETSENCRYPT_EMAIL}
    server: ${server}
    privateKeySecretRef:
      name: ${issuer}-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
  kubectl wait --for=condition=Ready "clusterissuer/${issuer}" --timeout=300s
}

require_file "$KUBECONFIG"
require_file kubernetes/bootstrap/namespaces.yaml
require_file kubernetes/base/blackbox-exporter-values.yaml
require_file kubernetes/base/alloy-values.yaml
require_file kubernetes/observability/grafana-dashboards.yaml
require_file kubernetes/observability/prometheus-rules.yaml
require_file kubernetes/observability/alloy-rbac.yaml
require_file kubernetes/observability/probes/platform-probes.yaml

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
apply_public_acme_issuer_if_requested

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

# Dashboards и alert rules живут отдельно от chart values, чтобы их можно было обновлять без смены Helm release.
kubectl apply -f kubernetes/observability/grafana-dashboards.yaml
kubectl apply -f kubernetes/observability/prometheus-rules.yaml

helm upgrade --install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --version "$BLACKBOX_EXPORTER_CHART_VERSION" \
  --namespace observability \
  --wait \
  --timeout 10m \
  -f kubernetes/base/blackbox-exporter-values.yaml

kubectl apply -f kubernetes/observability/probes/platform-probes.yaml

helm upgrade --install loki grafana/loki \
  --version "$LOKI_CHART_VERSION" \
  --namespace observability \
  --wait \
  --timeout 15m \
  -f kubernetes/base/loki-values.yaml

# RBAC для Alloy задаётся явно и минимально, вместо широких стандартных правил chart'а.
kubectl apply -f kubernetes/observability/alloy-rbac.yaml

helm upgrade --install alloy grafana/alloy \
  --version "$ALLOY_CHART_VERSION" \
  --namespace observability \
  --wait \
  --timeout 10m \
  -f kubernetes/base/alloy-values.yaml

kubectl get pods -A
kubectl get sc
kubectl get clusterissuer
