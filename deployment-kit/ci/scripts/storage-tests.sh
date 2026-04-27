#!/usr/bin/env bash
# Скрипт запускает проверку динамического PVC и сохранения данных.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/storage/pvc-read-write.sh

