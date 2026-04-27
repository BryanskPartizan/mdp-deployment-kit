#!/usr/bin/env bash
# Скрипт удаляет инфраструктуру окружения через Terraform и требует явного подтверждения.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
TF_DIR=terraform/vm
ART=.artifacts/${ENV_NAME}

if [[ "${CONFIRM_DESTROY:-}" != "$ENV_NAME" ]]; then
  echo "Удаление инфраструктуры требует подтверждения: CONFIRM_DESTROY=${ENV_NAME} make infra-destroy ENV=${ENV_NAME}" >&2
  exit 1
fi

mkdir -p "${ART}"
terraform -chdir="${TF_DIR}" init -input=false
terraform -chdir="${TF_DIR}" destroy \
  -input=false \
  -auto-approve \
  -var-file="../../environments/${ENV_NAME}/terraform.tfvars"

