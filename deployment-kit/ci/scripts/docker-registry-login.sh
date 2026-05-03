#!/usr/bin/env bash
# Скрипт настраивает Docker trust и выполняет docker login в GitLab registry без печати пароля.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
REGISTRY_HOST=${REGISTRY_HOST:-registry.${APP_DOMAIN}}
REGISTRY_USER=${REGISTRY_USER:-root}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_ROOT_SECRET=${GITLAB_ROOT_SECRET:-gitlab-root-password}
# Для публичного pkhco.ru с Let's Encrypt production Docker trust не требует дополнительных настроек.
REGISTRY_TRUST_MODE=${REGISTRY_TRUST_MODE:-none}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

require_command kubectl
require_command docker

case "$REGISTRY_TRUST_MODE" in
  insecure)
    "$(dirname "$0")/configure-docker-insecure-registry.sh"
    ;;
  ca)
    "$(dirname "$0")/configure-docker-registry-trust.sh" "$ENV_NAME"
    ;;
  none)
    echo "Настройка Docker trust пропущена: REGISTRY_TRUST_MODE=none."
    ;;
  *)
    echo "Неизвестный REGISTRY_TRUST_MODE=${REGISTRY_TRUST_MODE}. Используйте insecure, ca или none." >&2
    exit 1
    ;;
esac

if [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
  PASSWORD="$REGISTRY_PASSWORD"
else
  echo "Чтение пароля GitLab root из secret ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET}."
  PASSWORD=$(kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" \
    -o jsonpath='{.data.password}' | base64 --decode)
fi

echo "Docker login в ${REGISTRY_HOST} пользователем ${REGISTRY_USER}."
printf '%s' "$PASSWORD" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin
