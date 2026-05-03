#!/usr/bin/env bash
# Скрипт запускает неразрушающие проверки отказоустойчивости control plane.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start resilience "Проверки отказоустойчивости"

run_check "control plane health" ./tests/resilience/control-plane-health.sh

suite_finish
