#!/usr/bin/env bash
# Скрипт запускает управляемый drain worker-узла и возвращает его в кластер.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start fail-node "Проверка drain worker-узла"

run_check "worker drain and uncordon" ./tests/resilience/worker-drain.sh

suite_finish
