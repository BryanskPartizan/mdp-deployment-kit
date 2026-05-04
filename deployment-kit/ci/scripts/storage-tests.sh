#!/usr/bin/env bash
# Скрипт запускает проверку динамического PVC и сохранения данных.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start storage "Проверки хранения"

run_check "PVC write/read" ./tests/storage/pvc-read-write.sh

suite_finish
