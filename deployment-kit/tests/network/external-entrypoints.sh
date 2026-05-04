#!/usr/bin/env bash
# Проверяет внешние точки входа, созданные Terraform: API NLB и ingress NLB.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
TERRAFORM_OUTPUTS=${ARTIFACTS_DIR}/terraform-outputs.json
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
FRONTEND_HOST=${SMOKE_FRONTEND_HOST:-app.${APP_DOMAIN}}
GATEWAY_HOST=${SMOKE_GATEWAY_HOST:-gateway.${APP_DOMAIN}}

if [[ ! -f "$TERRAFORM_OUTPUTS" ]]; then
  echo "Terraform outputs не найдены, внешняя проверка NLB пропущена: $TERRAFORM_OUTPUTS"
  exit 0
fi

command -v jq >/dev/null || { echo "Для проверки Terraform outputs нужен jq." >&2; exit 1; }
command -v nc >/dev/null || { echo "Для проверки TCP endpoint нужен nc." >&2; exit 1; }
command -v curl >/dev/null || { echo "Для проверки ingress endpoint нужен curl." >&2; exit 1; }

API_IP=$(jq -r '.api_external_ip.value // empty' "$TERRAFORM_OUTPUTS")
INGRESS_IP=$(jq -r '.ingress_external_ip.value // empty' "$TERRAFORM_OUTPUTS")

if [[ -z "$API_IP" || -z "$INGRESS_IP" ]]; then
  echo "В terraform-outputs.json отсутствуют api_external_ip или ingress_external_ip." >&2
  exit 1
fi

echo "Проверка Kubernetes API NLB: ${API_IP}:6443"
nc -zvw5 "$API_IP" 6443

echo "Проверка frontend через ingress NLB: ${FRONTEND_HOST} -> ${INGRESS_IP}"
curl -kfsS --resolve "${FRONTEND_HOST}:443:${INGRESS_IP}" "https://${FRONTEND_HOST}/health" >/dev/null

echo "Проверка gateway через ingress NLB: ${GATEWAY_HOST} -> ${INGRESS_IP}"
curl -kfsS --resolve "${GATEWAY_HOST}:443:${INGRESS_IP}" "https://${GATEWAY_HOST}/health" >/dev/null
