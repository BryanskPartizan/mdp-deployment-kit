#!/usr/bin/env bash
# Скрипт выдаёт Vault token для входа в UI или создаёт короткоживущий admin token.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
MODE=${2:-${VAULT_TOKEN_MODE:-show-root}}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
KUBECONFIG_PATH=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
VAULT_NAMESPACE=${VAULT_NAMESPACE:-security}
VAULT_POD=${VAULT_POD:-vault-0}
VAULT_KEYS_FILE=${VAULT_KEYS_FILE:-${ARTIFACTS_DIR}/vault-init.json}
VAULT_ADMIN_TOKEN_TTL=${VAULT_ADMIN_TOKEN_TTL:-24h}
VAULT_ADMIN_TOKEN_FILE=${VAULT_ADMIN_TOKEN_FILE:-${ARTIFACTS_DIR}/vault-admin-token.json}

command -v jq >/dev/null || { echo "Для работы с Vault token нужен jq." >&2; exit 1; }
[[ -f "$VAULT_KEYS_FILE" ]] || { echo "Не найден $VAULT_KEYS_FILE. Сначала выполните make vault-init ENV=${ENV_NAME}." >&2; exit 1; }

ROOT_TOKEN=$(jq -r '.root_token // empty' "$VAULT_KEYS_FILE")
if [[ -z "$ROOT_TOKEN" || "$ROOT_TOKEN" == "null" ]]; then
  echo "В $VAULT_KEYS_FILE нет root_token." >&2
  exit 1
fi

case "$MODE" in
  show-root)
    echo "Root token из ${VAULT_KEYS_FILE}. Используйте только для bootstrap/debug; для UI лучше make vault-admin-token." >&2
    printf '%s\n' "$ROOT_TOKEN"
    ;;
  create-admin)
    [[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }
    case "$VAULT_ADMIN_TOKEN_TTL" in
      *[!0-9a-zA-Z]*|"")
        echo "VAULT_ADMIN_TOKEN_TTL должен быть простым Vault TTL, например 2h, 24h или 7d." >&2
        exit 1
        ;;
    esac

    mkdir -p "$ARTIFACTS_DIR"
    # Root token передаётся в Vault pod через stdin, чтобы не хранить его в аргументах kubectl процесса.
    printf '%s' "$ROOT_TOKEN" | kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec -i -c vault "$VAULT_POD" -- \
      sh -ec "VAULT_TOKEN=\$(cat) vault token create -policy=root -ttl='${VAULT_ADMIN_TOKEN_TTL}' -format=json" > "$VAULT_ADMIN_TOKEN_FILE"
    chmod 0600 "$VAULT_ADMIN_TOKEN_FILE"
    echo "Создан admin token с policy=root, TTL=${VAULT_ADMIN_TOKEN_TTL}. JSON сохранён в ${VAULT_ADMIN_TOKEN_FILE}." >&2
    jq -r '.auth.client_token' "$VAULT_ADMIN_TOKEN_FILE"
    ;;
  *)
    echo "Неизвестный режим: $MODE. Используйте show-root или create-admin." >&2
    exit 1
    ;;
esac
