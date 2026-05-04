#!/usr/bin/env bash
# Скрипт запускает проверки GitLab devops-контура.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
export ENV_NAME

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start gitlab "Проверки GitLab"

run_check "GitLab components and endpoints" ./tests/integration/gitlab.sh "$ENV_NAME"

suite_finish
