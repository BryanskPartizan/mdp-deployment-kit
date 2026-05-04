#!/usr/bin/env bash
# Проверяет готовность платформенных компонентов после deploy-platform.
set -euo pipefail

kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

kubectl -n cert-manager rollout status deployment/cert-manager --timeout=300s
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=300s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-prod --timeout=300s

if kubectl get clusterissuer -o name | grep -Eq 'clusterissuer/(selfsigned-bootstrap|test-selfsigned|letsencrypt-staging)$'; then
  echo "Найдены запрещенные non-prod ClusterIssuer. В публичном профиле должен остаться только letsencrypt-prod." >&2
  exit 1
fi

kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s
kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -qx "True"

kubectl -n observability get pods
kubectl -n observability wait --for=condition=Ready pods --all --timeout=600s

BLACKBOX_DEPLOYMENTS=$(kubectl -n observability get deployment -l app.kubernetes.io/name=prometheus-blackbox-exporter -o name)
[[ -n "$BLACKBOX_DEPLOYMENTS" ]] || { echo "Не найден deployment prometheus-blackbox-exporter" >&2; exit 1; }
while IFS= read -r deployment; do
  [[ -n "$deployment" ]] || continue
  kubectl -n observability rollout status "$deployment" --timeout=300s
done <<<"$BLACKBOX_DEPLOYMENTS"

kubectl -n observability get servicemonitor -l deployment-kit/component=endpoint-probe
kubectl -n observability rollout status daemonset/alloy --timeout=300s
kubectl -n observability get servicemonitor -l deployment-kit/component=alloy
kubectl get clusterrole deployment-kit-alloy
kubectl -n observability get prometheusrule deployment-kit-platform-alerts
kubectl -n observability get configmap deployment-kit-grafana-dashboards
kubectl -n observability get configmap deployment-kit-grafana-dashboards -o jsonpath='{.data.datastores\.json}' | grep -q "Redis and PostgreSQL"
kubectl -n observability get configmap deployment-kit-grafana-dashboards -o jsonpath='{.data.etcd\.json}' | grep -q "kube-etcd"
