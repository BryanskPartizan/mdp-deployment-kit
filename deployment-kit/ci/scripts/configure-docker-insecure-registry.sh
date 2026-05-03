#!/usr/bin/env bash
# Скрипт включает insecure registry для локального Docker daemon в demo-режиме с self-signed TLS.
set -euo pipefail

APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
GITLAB_HOST=${GITLAB_HOST:-gitlab.${APP_DOMAIN}}
REGISTRY_HOST=${REGISTRY_HOST:-registry.${APP_DOMAIN}}
RESTART_DOCKER=${RESTART_DOCKER:-true}

if [[ "$(uname -s)" == "Darwin" ]]; then
  DOCKER_DAEMON_JSON=${DOCKER_DAEMON_JSON:-$HOME/.docker/daemon.json}
else
  DOCKER_DAEMON_JSON=${DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}
fi

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

restart_docker_if_possible() {
  if [[ "$RESTART_DOCKER" != "true" ]]; then
    echo "Перезапуск Docker пропущен: RESTART_DOCKER=false."
    return
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    if command -v osascript >/dev/null 2>&1 && command -v open >/dev/null 2>&1; then
      echo "Перезапуск Docker Desktop, чтобы daemon перечитал ${DOCKER_DAEMON_JSON}."
      osascript -e 'quit app "Docker"' >/dev/null 2>&1 || true
      sleep 5
      open -a Docker
      return
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    echo "Перезапуск docker через systemctl."
    sudo systemctl restart docker
    return
  fi

  echo "Не удалось автоматически перезапустить Docker. Перезапустите Docker daemon вручную."
}

wait_for_docker() {
  if ! command -v docker >/dev/null 2>&1 || [[ "$RESTART_DOCKER" != "true" ]]; then
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

require_command ruby

mkdir -p "$(dirname "$DOCKER_DAEMON_JSON")"
if [[ ! -f "$DOCKER_DAEMON_JSON" ]]; then
  printf '{}\n' > "$DOCKER_DAEMON_JSON"
fi

BACKUP="${DOCKER_DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
cp "$DOCKER_DAEMON_JSON" "$BACKUP"
echo "Backup Docker daemon config: ${BACKUP}"

REGISTRY_HOST="$REGISTRY_HOST" GITLAB_HOST="$GITLAB_HOST" DOCKER_DAEMON_JSON="$DOCKER_DAEMON_JSON" ruby <<'RUBY'
require "json"

path = ENV.fetch("DOCKER_DAEMON_JSON")
config = JSON.parse(File.read(path))
current = Array(config["insecure-registries"])
desired = [
  ENV.fetch("REGISTRY_HOST"),
  "#{ENV.fetch("REGISTRY_HOST")}:443",
  ENV.fetch("GITLAB_HOST"),
  "#{ENV.fetch("GITLAB_HOST")}:443"
]

config["insecure-registries"] = (current + desired).uniq
File.write(path, JSON.pretty_generate(config) + "\n")
RUBY

echo "Docker daemon config обновлён:"
ruby -rjson -e 'puts JSON.pretty_generate(JSON.parse(File.read(ARGV[0])))' "$DOCKER_DAEMON_JSON"

restart_docker_if_possible
wait_for_docker

if command -v docker >/dev/null 2>&1; then
  echo "Проверка insecure registries в docker info:"
  docker info 2>/dev/null | sed -n '/Insecure Registries:/,/Live Restore Enabled:/p' || true
fi
