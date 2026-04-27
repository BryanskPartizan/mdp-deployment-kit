#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
NODE_NAME=${NODE_NAME:-$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')}

echo "Перевод узла в состояние cordon: ${NODE_NAME}"
kubectl cordon "${NODE_NAME}"
echo "Выполнение drain для узла: ${NODE_NAME}"
kubectl drain "${NODE_NAME}" --ignore-daemonsets --delete-emptydir-data --force

echo "Текущие pod прикладного контура после drain:"
kubectl get pods -n app -o wide
