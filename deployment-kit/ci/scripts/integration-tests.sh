#!/usr/bin/env bash
# Скрипт запускает интеграционные проверки приложений и Vault Injector.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/integration/platform-components.sh
./tests/integration/app-flow.sh
./tests/integration/vault-injection.sh
