#!/usr/bin/env bash
# Скрипт устанавливает Vault через Terraform-managed Helm release.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
KUBECONFIG_PATH=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
ROOT_DIR=$(pwd)

[[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }

# Vault хранит Raft-данные в PVC, поэтому перед Helm release гарантируем наличие local-path provisioner.
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f kubernetes/bootstrap/local-path-storage.yaml
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f kubernetes/bootstrap/storageclass.yaml
kubectl --kubeconfig "$KUBECONFIG_PATH" -n local-path-storage rollout status deployment/local-path-provisioner --timeout=300s

terraform -chdir=terraform/platform init -input=false
terraform -chdir=terraform/platform apply \
  -input=false \
  -auto-approve \
  -var="kubeconfig_path=${ROOT_DIR}/${KUBECONFIG_PATH}"

kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get pods,svc
