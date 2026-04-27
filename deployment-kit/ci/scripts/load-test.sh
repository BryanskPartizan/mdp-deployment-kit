#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail
TARGET_URL=${TARGET_URL:-https://gateway.lab.local/health}
k6 run -e TARGET_URL="${TARGET_URL}" tests/load/gateway-ramp.js
