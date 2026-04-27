#!/usr/bin/env bash
# Скрипт запускает проверки сетевой связанности кластера.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/network/connectivity.sh
./tests/network/external-entrypoints.sh "$ENV_NAME"
