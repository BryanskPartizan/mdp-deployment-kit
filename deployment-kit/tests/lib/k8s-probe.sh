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
  local phase=""
  local timeout_seconds="${TEST_POD_TIMEOUT%s}"
  local deadline

  name=$(probe_name)

  if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]]; then
    timeout_seconds=180
  fi

  kubectl -n "$namespace" run "$name" \
    --image="$TEST_IMAGE" \
    --restart=Never \
    --labels="$labels" \
    --command -- sh -ec "$command" >/dev/null

  deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    phase=$(kubectl -n "$namespace" get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "$phase" in
      Succeeded|Failed)
        break
        ;;
    esac
    sleep 1
  done

  kubectl -n "$namespace" logs "$name" --all-containers=true 2>/dev/null || true
  kubectl -n "$namespace" delete pod "$name" --ignore-not-found --wait=false >/dev/null 2>&1 || true

  case "$phase" in
    Succeeded)
      return 0
      ;;
    Failed)
      return 1
      ;;
    *)
      echo "Диагностический Pod ${namespace}/${name} не завершился за ${timeout_seconds}s, текущая phase=${phase:-unknown}." >&2
      kubectl -n "$namespace" describe pod "$name" >&2 || true
      return 2
      ;;
  esac
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

  if [[ "$exit_code" -eq 0 ]]; then
    echo "Ожидался запрет, но команда завершилась успешно: $title" >&2
    exit 1
  fi

  if [[ "$exit_code" -ne 1 ]]; then
    echo "Диагностический Pod не завершился ожидаемой ошибкой, результат запрета недостоверен." >&2
    exit 1
  fi
}

wait_rollout() {
  local namespace="$1"
  local kind="$2"
  local name="$3"

  kubectl -n "$namespace" rollout status "$kind/$name" --timeout=300s
}
