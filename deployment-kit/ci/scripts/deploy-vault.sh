#!/usr/bin/env bash
# Скрипт устанавливает Vault через Terraform-managed Helm release.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
KUBECONFIG_PATH=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
ROOT_DIR=$(pwd)

[[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }

terraform -chdir=terraform/platform init -input=false
terraform -chdir=terraform/platform apply \
  -input=false \
  -auto-approve \
  -var="kubeconfig_path=${ROOT_DIR}/${KUBECONFIG_PATH}"

kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get pods,svc

