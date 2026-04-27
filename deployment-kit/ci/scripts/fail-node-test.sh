#!/usr/bin/env bash
# Скрипт запускает управляемый drain worker-узла и возвращает его в кластер.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/resilience/worker-drain.sh
