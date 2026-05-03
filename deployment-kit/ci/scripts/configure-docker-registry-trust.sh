#!/usr/bin/env bash
# Скрипт настраивает доверие локального Docker daemon к self-signed CA стенда.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
GITLAB_HOST=${GITLAB_HOST:-gitlab.${APP_DOMAIN}}
REGISTRY_HOST=${REGISTRY_HOST:-registry.${APP_DOMAIN}}
CA_NAMESPACE=${CA_NAMESPACE:-cert-manager}
CA_SECRET=${CA_SECRET:-local-root-ca}
CA_FILE=${CA_FILE:-${ARTIFACTS_DIR}/local-root-ca.crt}
RESTART_DOCKER=${RESTART_DOCKER:-true}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

install_ca_for_host() {
  local host="$1"

  mkdir -p "$HOME/.docker/certs.d/${host}" "$HOME/.docker/certs.d/${host}:443"
  cp "$CA_FILE" "$HOME/.docker/certs.d/${host}/ca.crt"
  cp "$CA_FILE" "$HOME/.docker/certs.d/${host}:443/ca.crt"
}

restart_docker_desktop_if_possible() {
  if [[ "$RESTART_DOCKER" != "true" ]]; then
    echo "Перезапуск Docker Desktop пропущен: RESTART_DOCKER=false."
    return
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Автоматический restart Docker Desktop поддержан только для macOS. Перезапустите Docker daemon вручную."
    return
  fi

  if ! command -v osascript >/dev/null 2>&1 || ! command -v open >/dev/null 2>&1; then
    echo "Не найдены osascript/open, перезапустите Docker Desktop вручную."
    return
  fi

  echo "Перезапуск Docker Desktop, чтобы daemon перечитал ~/.docker/certs.d."
  osascript -e 'quit app "Docker"' >/dev/null 2>&1 || true
  sleep 5
  open -a Docker
}

wait_for_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  if [[ "$RESTART_DOCKER" != "true" ]]; then
    return
  fi

  echo "Ожидание готовности Docker daemon."
  for _ in {1..90}; do
    if docker info >/dev/null 2>&1; then
      echo "Docker daemon готов."
      return
    fi
    sleep 2
  done

  echo "Docker daemon не стал доступен за ожидаемое время." >&2
  exit 1
}

require_command kubectl
require_command openssl

mkdir -p "$ARTIFACTS_DIR"

echo "Экспорт CA ${CA_NAMESPACE}/${CA_SECRET} в ${CA_FILE}."
kubectl -n "$CA_NAMESPACE" get secret "$CA_SECRET" \
  -o jsonpath='{.data.tls\.crt}' | base64 --decode > "$CA_FILE"
chmod 0644 "$CA_FILE"

echo "Проверка CA:"
openssl x509 -in "$CA_FILE" -noout -subject -issuer -dates

install_ca_for_host "$REGISTRY_HOST"
install_ca_for_host "$GITLAB_HOST"

echo "CA установлен в:"
echo "  $HOME/.docker/certs.d/${REGISTRY_HOST}/ca.crt"
echo "  $HOME/.docker/certs.d/${REGISTRY_HOST}:443/ca.crt"
echo "  $HOME/.docker/certs.d/${GITLAB_HOST}/ca.crt"
echo "  $HOME/.docker/certs.d/${GITLAB_HOST}:443/ca.crt"

restart_docker_desktop_if_possible
wait_for_docker
