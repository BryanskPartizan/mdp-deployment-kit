#!/usr/bin/env bash
# Проверяет готовность платформенных компонентов после deploy-platform.
set -euo pipefail

kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

kubectl -n cert-manager rollout status deployment/cert-manager --timeout=300s
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=300s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s
kubectl wait --for=condition=Ready clusterissuer/selfsigned-bootstrap --timeout=300s
kubectl wait --for=condition=Ready clusterissuer/test-selfsigned --timeout=300s

kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s
kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -qx "True"

kubectl -n observability get pods
kubectl -n observability wait --for=condition=Ready pods --all --timeout=600s

