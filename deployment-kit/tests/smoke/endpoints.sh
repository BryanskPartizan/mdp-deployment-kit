#!/usr/bin/env bash
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
TERRAFORM_OUTPUTS=${ARTIFACTS_DIR}/terraform-outputs.json
APP_DOMAIN=${APP_DOMAIN:-mdp}

# Проверяем, что прикладные сервисы и сетевые политики действительно созданы.
kubectl -n app get svc api gateway frontend
kubectl -n app get ingress -o wide
kubectl -n app get networkpolicy
kubectl -n app get pvc

# Если Terraform outputs доступны, проверяем публикацию ingress через внешний NLB.
if [[ -f "$TERRAFORM_OUTPUTS" ]] && command -v jq >/dev/null && command -v curl >/dev/null; then
  INGRESS_IP=$(jq -r '.ingress_external_ip.value // empty' "$TERRAFORM_OUTPUTS")
  FRONTEND_HOST=${SMOKE_FRONTEND_HOST:-app.${APP_DOMAIN}}

  if [[ -n "$INGRESS_IP" ]]; then
    curl -kfsS --resolve "${FRONTEND_HOST}:443:${INGRESS_IP}" "https://${FRONTEND_HOST}/health" >/dev/null
  fi
fi
