#!/usr/bin/env bash
# Скрипт запускает проверки сетевой связанности кластера.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start network "Сетевые проверки"

run_check "внутрикластерная связанность" ./tests/network/connectivity.sh
run_check "внешние entrypoint'ы" ./tests/network/external-entrypoints.sh "$ENV_NAME"

suite_finish
