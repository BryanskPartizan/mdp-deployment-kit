#!/usr/bin/env bash
# Скрипт выполняет первичный init/unseal Vault и сохраняет bootstrap-ключи в локальные артефакты окружения.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
KUBECONFIG_PATH=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
VAULT_NAMESPACE=${VAULT_NAMESPACE:-security}
VAULT_KEYS_FILE=${ARTIFACTS_DIR}/vault-init.json

command -v jq >/dev/null || { echo "Для init/unseal Vault нужен jq." >&2; exit 1; }
[[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }

vault_status_json() {
  local pod=$1
  local raw
  local json

  set +e
  raw=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec -c vault "$pod" -- vault status -format=json 2>/dev/null)
  set -e

  json=$(sed -n '/^[[:space:]]*{/,/^[[:space:]]*}/p' <<<"${raw:-}")
  if [[ -z "$json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$json"; then
    return 1
  fi

  printf '%s\n' "$json"
}

wait_vault_initialized() {
  local pod=$1
  local status_json
  local initialized

  for ((attempt = 1; attempt <= 60; attempt++)); do
    if status_json=$(vault_status_json "$pod"); then
      initialized=$(jq -r '.initialized // false' <<<"$status_json")
      if [[ "$initialized" == "true" ]]; then
        printf '%s\n' "$status_json"
        return 0
      fi
    fi
    sleep 5
  done

  return 1
}

mkdir -p "$ARTIFACTS_DIR"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" wait --for=condition=PodScheduled pod/vault-0 --timeout=300s

if ! STATUS_JSON=$(vault_status_json vault-0); then
  echo "Не удалось получить корректный JSON из 'vault status -format=json'." >&2
  exit 1
fi

INITIALIZED=$(jq -r '.initialized // false' <<<"$STATUS_JSON")

if [[ "$INITIALIZED" != "true" ]]; then
  VAULT_KEYS_RAW_FILE="${VAULT_KEYS_FILE}.raw"
  rm -f "$VAULT_KEYS_RAW_FILE" "$VAULT_KEYS_FILE"

  set +e
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec -c vault vault-0 -- \
    vault operator init -key-shares=5 -key-threshold=3 -format=json > "$VAULT_KEYS_RAW_FILE"
  INIT_CODE=$?
  set -e

  sed -n '/^[[:space:]]*{/,/^[[:space:]]*}/p' "$VAULT_KEYS_RAW_FILE" > "$VAULT_KEYS_FILE"
  rm -f "$VAULT_KEYS_RAW_FILE"

  if [[ "$INIT_CODE" -ne 0 ]] || ! jq -e . "$VAULT_KEYS_FILE" >/dev/null; then
    # Файл содержит root token и unseal keys, поэтому при ошибке не печатаем его содержимое в logs.
    rm -f "$VAULT_KEYS_FILE"
    echo "Vault init не вернул корректный JSON. Проверьте состояние pod/vault-0 и повторите vault-init." >&2
    exit 1
  fi

  chmod 0600 "$VAULT_KEYS_FILE"
  echo "Vault initialized, bootstrap material saved to $VAULT_KEYS_FILE"
elif [[ ! -f "$VAULT_KEYS_FILE" ]]; then
  echo "Vault уже initialized, но $VAULT_KEYS_FILE не найден. Для unseal нужен сохранённый набор ключей." >&2
  exit 1
fi

UNSEAL_KEYS=()
while IFS= read -r key; do
  UNSEAL_KEYS+=("$key")
done < <(jq -r '.unseal_keys_b64[0:3][]' "$VAULT_KEYS_FILE")

VAULT_PODS=()
while IFS= read -r pod; do
  VAULT_PODS+=("$pod")
done < <(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get pods -o json | jq -r '.items[].metadata.name | select(test("^vault-[0-9]+$"))' | sort)

if [[ "${#VAULT_PODS[@]}" -eq 0 ]]; then
  echo "Не найдены Vault server Pod'ы для unseal." >&2
  exit 1
fi

# Unseal выполняется по фактическому списку Pod'ов, чтобы replicas можно было менять в Helm values.
for pod in "${VAULT_PODS[@]}"; do
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" wait --for=condition=PodScheduled "pod/${pod}" --timeout=300s

  if ! STATUS_JSON=$(wait_vault_initialized "$pod"); then
    echo "Vault pod ${pod} не стал initialized=true. Проверьте retry_join и логи Vault." >&2
    exit 1
  fi

  SEALED=$(jq -r '.sealed // true' <<<"$STATUS_JSON")
  if [[ "$SEALED" == "true" ]]; then
    for key in "${UNSEAL_KEYS[@]}"; do
      kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec -c vault "$pod" -- vault operator unseal "$key" >/dev/null
    done
  fi

  # После unseal readiness probe должна увидеть initialized=true и sealed=false.
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" wait --for=condition=Ready "pod/${pod}" --timeout=300s
done

kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get pods
