#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

INGRESS_NGINX_CHART_VERSION=${INGRESS_NGINX_CHART_VERSION:-4.15.1}
CERT_MANAGER_VERSION=${CERT_MANAGER_VERSION:-v1.19.5}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-3.13.0}
PROMETHEUS_STACK_CHART_VERSION=${PROMETHEUS_STACK_CHART_VERSION:-84.3.0}
BLACKBOX_EXPORTER_CHART_VERSION=${BLACKBOX_EXPORTER_CHART_VERSION:-11.9.1}
LOKI_CHART_VERSION=${LOKI_CHART_VERSION:-7.0.0}
ALLOY_CHART_VERSION=${ALLOY_CHART_VERSION:-1.8.0}
HEADLAMP_CHART_VERSION=${HEADLAMP_CHART_VERSION:-0.41.0}
K8S_ADMIN_ENABLED=${K8S_ADMIN_ENABLED:-false}
K8S_ADMIN_BASIC_AUTH_SECRET=${K8S_ADMIN_BASIC_AUTH_SECRET:-headlamp-basic-auth}
ALLOW_INSECURE_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}
GRAFANA_HOST=${GRAFANA_HOST:-grafana.${APP_DOMAIN}}
K8S_ADMIN_HOST=${K8S_ADMIN_HOST:-k8s-admin.${APP_DOMAIN}}

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

remove_staging_issuer() {
  # Тестовый Let's Encrypt запрещён для стенда: Docker и клиенты не доверяют staging CA.
  kubectl delete clusterissuer letsencrypt-staging --ignore-not-found
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

  if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]] && kubectl -n observability get secret grafana-admin >/dev/null 2>&1; then
    echo "Secret observability/grafana-admin уже существует; повторно используем его."
    return
  fi

  password=$(secret_or_demo GRAFANA_ADMIN_PASSWORD "admin-demo-password-change-me")

  kubectl -n observability delete secret grafana-admin --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n observability create secret generic grafana-admin \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER:-admin}" \
    --from-literal=admin-password="$password"
}

create_headlamp_basic_auth_secret() {
  if [[ "$K8S_ADMIN_ENABLED" != "true" ]]; then
    return
  fi

  if [[ -z "${K8S_ADMIN_BASIC_AUTH_HTPASSWD:-}" ]]; then
    echo "Задайте K8S_ADMIN_BASIC_AUTH_HTPASSWD для публикации k8s-admin. Пример: htpasswd -nbB admin '<strong-password>'" >&2
    exit 1
  fi

  # Публичная k8s-админка защищается на уровне ingress-nginx, так как Cloudflare proxy/Access выключен.
  kubectl create namespace k8s-admin --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n k8s-admin delete secret "$K8S_ADMIN_BASIC_AUTH_SECRET" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n k8s-admin create secret generic "$K8S_ADMIN_BASIC_AUTH_SECRET" \
    --from-literal=auth="$K8S_ADMIN_BASIC_AUTH_HTPASSWD"
}

apply_public_acme_issuer_if_requested() {
  local issuer="$TLS_CLUSTER_ISSUER"

  if [[ "$issuer" != "letsencrypt-prod" ]]; then
    return
  fi

  if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    echo "Для TLS_CLUSTER_ISSUER=${issuer} задайте LETSENCRYPT_EMAIL. Для приватного домена mdp используйте test-selfsigned." >&2
    exit 1
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
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: ${issuer}-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
  kubectl wait --for=condition=Ready "clusterissuer/${issuer}" --timeout=300s
}

render_platform_domain_values() {
  local output
  output=$(mktemp)
  # Grafana публикуется через тот же ingress NLB, что и остальные публичные точки входа.
  cat > "$output" <<EOF
grafana:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: ${TLS_CLUSTER_ISSUER}
    hosts:
      - ${GRAFANA_HOST}
    tls:
      - secretName: grafana-tls
        hosts:
          - ${GRAFANA_HOST}
EOF
  echo "$output"
}

render_headlamp_domain_values() {
  local output
  output=$(mktemp)
  # Headlamp включается явно: публичная k8s-админка требует отдельного контроля доступа.
  cat > "$output" <<EOF
ingress:
  annotations:
    cert-manager.io/cluster-issuer: ${TLS_CLUSTER_ISSUER}
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: ${K8S_ADMIN_BASIC_AUTH_SECRET}
    nginx.ingress.kubernetes.io/auth-realm: "Kubernetes admin"
  hosts:
    - host: ${K8S_ADMIN_HOST}
      paths:
        - path: /
          type: Prefix
  tls:
    - secretName: headlamp-tls
      hosts:
        - ${K8S_ADMIN_HOST}
EOF
  echo "$output"
}

require_file "$KUBECONFIG"
validate_tls_issuer
remove_staging_issuer
require_file kubernetes/bootstrap/namespaces.yaml
require_file kubernetes/base/blackbox-exporter-values.yaml
require_file kubernetes/base/alloy-values.yaml
require_file kubernetes/base/headlamp-values.yaml
require_file kubernetes/observability/grafana-dashboards.yaml
require_file kubernetes/observability/prometheus-rules.yaml
require_file kubernetes/observability/alloy-rbac.yaml
require_file kubernetes/observability/probes/platform-probes.yaml

kubectl apply -f kubernetes/bootstrap/namespaces.yaml
kubectl apply -f kubernetes/bootstrap/local-path-storage.yaml
kubectl apply -f kubernetes/bootstrap/storageclass.yaml
wait_rollout local-path-storage deployment local-path-provisioner
create_grafana_secret
create_headlamp_basic_auth_secret
PLATFORM_DOMAIN_VALUES_FILE=$(render_platform_domain_values)
HEADLAMP_DOMAIN_VALUES_FILE=$(render_headlamp_domain_values)
trap 'rm -f "$PLATFORM_DOMAIN_VALUES_FILE" "$HEADLAMP_DOMAIN_VALUES_FILE"' EXIT

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null 2>&1 || true
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "$PROMETHEUS_STACK_CHART_VERSION" \
  --namespace observability \
  --create-namespace \
  --wait \
  --timeout 15m \
  -f kubernetes/base/prometheus-stack-values.yaml \
  -f "$PLATFORM_DOMAIN_VALUES_FILE"

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

# Дашборды и правила алертов живут отдельно от chart values, чтобы их можно было обновлять без смены Helm release.
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

if [[ "$K8S_ADMIN_ENABLED" == "true" ]]; then
  helm upgrade --install headlamp headlamp/headlamp \
    --version "$HEADLAMP_CHART_VERSION" \
    --namespace k8s-admin \
    --create-namespace \
    --wait \
    --timeout 10m \
    -f kubernetes/base/headlamp-values.yaml \
    -f "$HEADLAMP_DOMAIN_VALUES_FILE"
fi

kubectl get pods -A
kubectl get sc
kubectl get clusterissuer
