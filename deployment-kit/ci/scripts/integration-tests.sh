#!/usr/bin/env bash
# Скрипт запускает интеграционные проверки приложений и Vault Injector.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start integration "Интеграционные проверки"

run_check "платформенные компоненты" ./tests/integration/platform-components.sh
run_check "прикладной flow лидов" ./tests/integration/app-flow.sh
run_check "Vault Agent Injector" ./tests/integration/vault-injection.sh

suite_finish
