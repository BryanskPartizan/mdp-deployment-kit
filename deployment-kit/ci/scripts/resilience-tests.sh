#!/usr/bin/env bash
# Скрипт запускает неразрушающие проверки отказоустойчивости control plane.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/resilience/control-plane-health.sh

