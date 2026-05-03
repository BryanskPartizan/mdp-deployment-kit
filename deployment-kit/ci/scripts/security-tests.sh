#!/usr/bin/env bash
# Скрипт запускает проверки безопасности: NetworkPolicy и RBAC.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start security "Проверки безопасности"

run_check "NetworkPolicy deny/allow" ./tests/security/network-policy.sh
run_check "RBAC service accounts" ./tests/security/rbac.sh

suite_finish
