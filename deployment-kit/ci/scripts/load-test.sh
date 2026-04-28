#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail
APP_DOMAIN=${APP_DOMAIN:-mdp}
TARGET_URL=${TARGET_URL:-https://gateway.${APP_DOMAIN}/health}
# Стартовый TLS-режим использует self-signed сертификаты, поэтому k6 по умолчанию не должен падать на trust chain.
export K6_INSECURE_SKIP_TLS_VERIFY=${K6_INSECURE_SKIP_TLS_VERIFY:-true}
k6 run -e TARGET_URL="${TARGET_URL}" tests/load/gateway-ramp.js
