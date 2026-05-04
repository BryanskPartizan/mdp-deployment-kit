#!/usr/bin/env bash
# Скрипт выполняет docker login в GitLab registry без печати пароля.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
REGISTRY_HOST=${REGISTRY_HOST:-registry.${APP_DOMAIN}}
REGISTRY_USER=${REGISTRY_USER:-root}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_ROOT_SECRET=${GITLAB_ROOT_SECRET:-gitlab-root-password}
# Публичный профиль использует только production Let's Encrypt, поэтому Docker trust не настраивается.
REGISTRY_TRUST_MODE=${REGISTRY_TRUST_MODE:-none}

is_placeholder() {
  [[ "${1:-}" == REPLACE_WITH_* ]]
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

require_command kubectl
require_command docker

if is_placeholder "$REGISTRY_USER"; then
  REGISTRY_USER=root
fi

if is_placeholder "${REGISTRY_PASSWORD:-}"; then
  unset REGISTRY_PASSWORD
fi

if [[ "$REGISTRY_TRUST_MODE" != "none" ]]; then
  echo "REGISTRY_TRUST_MODE=${REGISTRY_TRUST_MODE} запрещён. Публичный профиль должен использовать валидный production Let's Encrypt сертификат." >&2
  exit 1
fi
echo "Docker trust не настраивается: registry должен иметь production Let's Encrypt сертификат."

if [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
  PASSWORD="$REGISTRY_PASSWORD"
else
  echo "Чтение пароля GitLab root из secret ${GITLAB_NAMESPACE}/${GITLAB_ROOT_SECRET}."
  PASSWORD=$(kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" \
    -o jsonpath='{.data.password}' | base64 --decode)
fi

echo "Docker login в ${REGISTRY_HOST} пользователем ${REGISTRY_USER}."
printf '%s' "$PASSWORD" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin
