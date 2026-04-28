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

mkdir -p "$ARTIFACTS_DIR"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" wait --for=condition=PodScheduled pod/vault-0 --timeout=300s

set +e
STATUS_JSON=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec vault-0 -- vault status -format=json 2>/dev/null)
STATUS_CODE=$?
set -e

INITIALIZED=$(jq -r '.initialized // false' <<<"${STATUS_JSON:-{}}")
SEALED=$(jq -r '.sealed // true' <<<"${STATUS_JSON:-{}}")

if [[ "$INITIALIZED" != "true" ]]; then
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec vault-0 -- \
    vault operator init -key-shares=5 -key-threshold=3 -format=json > "$VAULT_KEYS_FILE"
  chmod 0600 "$VAULT_KEYS_FILE"
  echo "Vault initialized, bootstrap material saved to $VAULT_KEYS_FILE"
elif [[ ! -f "$VAULT_KEYS_FILE" ]]; then
  echo "Vault уже initialized, но $VAULT_KEYS_FILE не найден. Для unseal нужен сохранённый набор ключей." >&2
  exit 1
fi

if [[ "$SEALED" == "true" || "$STATUS_CODE" -eq 2 ]]; then
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
    for key in "${UNSEAL_KEYS[@]}"; do
      kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" exec "$pod" -- vault operator unseal "$key" >/dev/null
    done
  done
fi

kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get pods
