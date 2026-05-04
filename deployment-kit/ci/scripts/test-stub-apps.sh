#!/usr/bin/env bash
# Скрипт запускает прикладные заглушки локально и проверяет create/get путь без Kubernetes.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
API_PORT=${API_PORT:-18081}
GATEWAY_PORT=${GATEWAY_PORT:-18080}
FRONTEND_PORT=${FRONTEND_PORT:-18082}

PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

wait_http() {
  local url="$1"
  local attempt

  for attempt in {1..30}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  echo "Endpoint не стал доступен: $url" >&2
  exit 1
}

json_field() {
  local field="$1"
  sed -n "s/.*\"${field}\":\"\\([^\"]*\\)\".*/\\1/p"
}

require_command node
require_command curl

(
  cd "$ROOT_DIR"
  HOST=127.0.0.1 PORT="$API_PORT" REDIS_URL=memory://local ENVIRONMENT=test node apps/api/server.js
) &
PIDS+=("$!")

(
  cd "$ROOT_DIR"
  HOST=127.0.0.1 PORT="$GATEWAY_PORT" API_BASE_URL="http://127.0.0.1:${API_PORT}" ENVIRONMENT=test node apps/gateway/server.js
) &
PIDS+=("$!")

(
  cd "$ROOT_DIR"
  HOST=127.0.0.1 PORT="$FRONTEND_PORT" GATEWAY_BASE_URL="http://127.0.0.1:${GATEWAY_PORT}" ENVIRONMENT=test node apps/frontend/server.js
) &
PIDS+=("$!")

wait_http "http://127.0.0.1:${API_PORT}/health"
wait_http "http://127.0.0.1:${GATEWAY_PORT}/health"
wait_http "http://127.0.0.1:${FRONTEND_PORT}/health"

echo "Проверка create/get lead через gateway"
GATEWAY_RESPONSE=$(curl -fsS \
  -H 'content-type: application/json' \
  -d '{"name":"Gateway Local Lead","company":"Deployment Kit","status":"qualified","budget":50000}' \
  "http://127.0.0.1:${GATEWAY_PORT}/leads")
GATEWAY_ID=$(printf '%s' "$GATEWAY_RESPONSE" | json_field id)
test -n "$GATEWAY_ID"
curl -fsS "http://127.0.0.1:${GATEWAY_PORT}/leads/${GATEWAY_ID}" | grep -q "Gateway Local Lead"

echo "Проверка update/get lead через frontend proxy"
FRONTEND_RESPONSE=$(curl -fsS \
  -H 'content-type: application/json' \
  -d '{"name":"Frontend Local Lead","company":"Deployment Kit","status":"new","budget":10000}' \
  "http://127.0.0.1:${FRONTEND_PORT}/leads")
FRONTEND_ID=$(printf '%s' "$FRONTEND_RESPONSE" | json_field id)
test -n "$FRONTEND_ID"
curl -fsS \
  -X PATCH \
  -H 'content-type: application/json' \
  -d '{"status":"won","budget":12000}' \
  "http://127.0.0.1:${FRONTEND_PORT}/leads/${FRONTEND_ID}" | grep -q '"status":"won"'

echo "Проверка публикации test run в админку frontend"
curl -fsS \
  -H 'content-type: application/json' \
  -d '{"suite":"local","title":"Local stub checks","status":"ok","durationSeconds":1,"checks":[{"status":"ok","title":"lead flow","durationSeconds":1}]}' \
  "http://127.0.0.1:${FRONTEND_PORT}/test-runs" | grep -q "Local stub checks"
curl -fsS "http://127.0.0.1:${FRONTEND_PORT}/test-runs" | grep -q "Local stub checks"

curl -fsS "http://127.0.0.1:${FRONTEND_PORT}/" | grep -q "Deployment Kit CRM"

echo "Stub apps tests passed."
