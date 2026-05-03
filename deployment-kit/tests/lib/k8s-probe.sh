#!/usr/bin/env bash
# Общие функции для запуска временных диагностических Pod'ов в Kubernetes.
set -euo pipefail

TEST_IMAGE=${TEST_IMAGE:-nicolaka/netshoot:v0.13}
TEST_POD_TIMEOUT=${TEST_POD_TIMEOUT:-180s}
TEST_COMMAND_TIMEOUT=${TEST_COMMAND_TIMEOUT:-8}
TEST_PREFIX=${TEST_PREFIX:-dk-test}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

probe_name() {
  printf "%s-%s-%s" "$TEST_PREFIX" "$(date +%s)" "$RANDOM"
}

run_probe() {
  local namespace="$1"
  local labels="$2"
  local command="$3"
  local name

  name=$(probe_name)
  kubectl -n "$namespace" run "$name" \
    --image="$TEST_IMAGE" \
    --restart=Never \
    --labels="$labels" \
    --pod-running-timeout="$TEST_POD_TIMEOUT" \
    --rm \
    -i \
    --attach \
    --command -- sh -ec "$command"
}

expect_success() {
  local title="$1"
  local namespace="$2"
  local labels="$3"
  local command="$4"

  echo "Проверка разрешения: $title"
  run_probe "$namespace" "$labels" "$command"
}

expect_failure() {
  local title="$1"
  local namespace="$2"
  local labels="$3"
  local command="$4"
  local output
  local exit_code

  echo "Проверка запрета: $title"
  set +e
  output=$(run_probe "$namespace" "$labels" "echo PROBE_STARTED; $command" 2>&1)
  exit_code=$?
  set -e

  echo "$output"

  # Маркер защищает от ложноположительного результата, когда Pod вообще не стартовал.
  if ! grep -q "PROBE_STARTED" <<<"$output"; then
    echo "Диагностический Pod не стартовал, результат запрета недостоверен." >&2
    exit 1
  fi

  if [[ "$exit_code" -eq 0 ]]; then
    echo "Ожидался запрет, но команда завершилась успешно: $title" >&2
    exit 1
  fi
}

wait_rollout() {
  local namespace="$1"
  local kind="$2"
  local name="$3"

  kubectl -n "$namespace" rollout status "$kind/$name" --timeout=300s
}
