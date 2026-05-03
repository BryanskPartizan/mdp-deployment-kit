#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_NAME=${1:-vm-dev}
export ENV_NAME
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TARGET_URL=${TARGET_URL:-https://gateway.${APP_DOMAIN}/health}
# Стартовый TLS-режим использует self-signed сертификаты, поэтому k6 по умолчанию не должен падать на trust chain.
export K6_INSECURE_SKIP_TLS_VERIFY=${K6_INSECURE_SKIP_TLS_VERIFY:-true}

cd "$ROOT_DIR"
source tests/lib/test-output.sh

suite_start load "Нагрузочная проверка"

run_check "k6 gateway ramp" k6 run -e TARGET_URL="${TARGET_URL}" tests/load/gateway-ramp.js

suite_finish
