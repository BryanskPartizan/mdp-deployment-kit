#!/usr/bin/env bash
# Скрипт запускает проверки GitLab devops-контура.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

./tests/integration/gitlab.sh "$ENV_NAME"

