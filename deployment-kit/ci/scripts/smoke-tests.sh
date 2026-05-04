#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start smoke "Smoke-проверки"

run_check "готовность узлов, namespace и Pod'ов" ./tests/smoke/healthcheck.sh
run_check "прикладные Service/Ingress/PVC" ./tests/smoke/endpoints.sh "$ENV_NAME"
run_check "rollout api" kubectl -n app rollout status deployment/api --timeout=300s
run_check "rollout gateway" kubectl -n app rollout status deployment/gateway --timeout=300s
run_check "rollout frontend" kubectl -n app rollout status deployment/frontend --timeout=300s
run_check "ingress приложения" kubectl -n app get ingress
run_check "cluster issuers" kubectl get clusterissuer -o wide
run_check "service accounts приложений" kubectl -n app get serviceaccount api gateway frontend

suite_finish
