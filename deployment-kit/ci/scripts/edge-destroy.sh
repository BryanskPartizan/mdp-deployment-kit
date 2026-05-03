#!/usr/bin/env bash
# Скрипт удаляет edge-слой: DNS records, CDN и связанные публичные edge-ресурсы.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
TF_DIR=terraform/edge
ART=.artifacts/${ENV_NAME}
VM_OUTPUTS="${ART}/terraform-outputs.json"
EDGE_VARS="environments/${ENV_NAME}/edge.tfvars"

if [[ "${CONFIRM_EDGE_DESTROY:-}" != "$ENV_NAME" ]]; then
  echo "Удаление edge-слоя требует подтверждения: CONFIRM_EDGE_DESTROY=${ENV_NAME} make edge-destroy ENV=${ENV_NAME}" >&2
  exit 1
fi

require_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Не найден обязательный файл: $path" >&2; exit 1; }
}

read_vm_output() {
  local key="$1"
  jq -r ".${key}.value // empty" "$VM_OUTPUTS"
}

require_file "$VM_OUTPUTS"
require_file "$EDGE_VARS"
command -v jq >/dev/null || { echo "Для edge-destroy нужен jq." >&2; exit 1; }

INGRESS_IP=$(read_vm_output ingress_external_ip)
NETWORK_ID=$(read_vm_output network_id)

if [[ -z "$INGRESS_IP" ]]; then
  echo "В ${VM_OUTPUTS} отсутствует ingress_external_ip. Для destroy edge-слоя нужен последний Terraform output vm-слоя." >&2
  exit 1
fi

TF_VAR_ARGS=(-var "ingress_external_ip=${INGRESS_IP}")
if [[ -n "$NETWORK_ID" ]]; then
  TF_VAR_ARGS+=(-var "private_network_ids=[\"${NETWORK_ID}\"]")
fi

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" destroy \
  -input=false \
  -auto-approve \
  -var-file="../../${EDGE_VARS}" \
  "${TF_VAR_ARGS[@]}"
