#!/usr/bin/env bash
# Скрипт запускает Terraform-конфигурацию Vault через локальный port-forward к service/vault.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
KUBECONFIG_PATH=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
VAULT_NAMESPACE=${VAULT_NAMESPACE:-security}
VAULT_KEYS_FILE=${ARTIFACTS_DIR}/vault-init.json
KUBE_CA_FILE=${ARTIFACTS_DIR}/vault-kubernetes-ca.crt
PORT_FORWARD_LOG=${ARTIFACTS_DIR}/vault-port-forward.log

command -v jq >/dev/null || { echo "Для настройки Vault нужен jq." >&2; exit 1; }
[[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }
[[ -f "$VAULT_KEYS_FILE" ]] || { echo "Не найден $VAULT_KEYS_FILE. Сначала выполните make vault-init ENV=${ENV_NAME}." >&2; exit 1; }

mkdir -p "$ARTIFACTS_DIR"

TOKEN_REVIEWER_JWT=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get secret vault-auth-token -o json | jq -r '.data.token | @base64d')
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get secret vault-auth-token -o json | jq -r '.data["ca.crt"] | @base64d' > "$KUBE_CA_FILE"
KUBERNETES_HOST=$(kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw -o jsonpath='{.clusters[0].cluster.server}')
VAULT_TOKEN=$(jq -r '.root_token' "$VAULT_KEYS_FILE")

kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" port-forward svc/vault 8200:8200 > "$PORT_FORWARD_LOG" 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true' EXIT

VAULT_READY=false
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:8200/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204" >/dev/null; then
    VAULT_READY=true
    break
  fi
  sleep 2
done

if [[ "$VAULT_READY" != "true" ]]; then
  echo "Vault API не стал доступен через port-forward. Лог: $PORT_FORWARD_LOG" >&2
  exit 1
fi

export TF_VAR_vault_addr="http://127.0.0.1:8200"
export TF_VAR_vault_token="$VAULT_TOKEN"
export TF_VAR_token_reviewer_jwt="$TOKEN_REVIEWER_JWT"

terraform -chdir=terraform/vault init -input=false
terraform -chdir=terraform/vault apply \
  -input=false \
  -auto-approve \
  -var="kubernetes_host=${KUBERNETES_HOST}" \
  -var="kubernetes_ca_cert_path=../../${KUBE_CA_FILE}"
