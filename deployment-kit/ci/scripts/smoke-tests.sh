#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/smoke/healthcheck.sh
./tests/smoke/endpoints.sh "$ENV_NAME"

kubectl -n app rollout status deployment/api --timeout=300s
kubectl -n app rollout status deployment/gateway --timeout=300s
kubectl -n app rollout status deployment/frontend --timeout=300s
kubectl -n app get ingress
kubectl get clusterissuer test-selfsigned -o wide
kubectl -n app get serviceaccount api gateway frontend
