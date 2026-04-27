#!/usr/bin/env bash
# Скрипт запускает проверки безопасности: NetworkPolicy и RBAC.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/security/network-policy.sh
./tests/security/rbac.sh

