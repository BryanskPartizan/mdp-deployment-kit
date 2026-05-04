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
VAULT_LOCAL_PORT=${VAULT_LOCAL_PORT:-8200}
ALLOW_DEMO_SECRETS=${ALLOW_INSECURE_DEMO_SECRETS:-false}

command -v jq >/dev/null || { echo "Для настройки Vault нужен jq." >&2; exit 1; }
[[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }
[[ -f "$VAULT_KEYS_FILE" ]] || { echo "Не найден $VAULT_KEYS_FILE. Сначала выполните make vault-init ENV=${ENV_NAME}." >&2; exit 1; }

mkdir -p "$ARTIFACTS_DIR"

case "$ALLOW_DEMO_SECRETS" in
  true|false) ;;
  *)
    echo "ALLOW_INSECURE_DEMO_SECRETS должен быть true или false." >&2
    exit 1
    ;;
esac

APP_SECRET_OVERRIDE_ARGS=()
if [[ -n "${TF_VAR_app_secret_overrides:-}" ]]; then
  if ! jq -e 'type == "object" and all(.[]; type == "object")' >/dev/null 2>&1 <<<"$TF_VAR_app_secret_overrides"; then
    if [[ "$ALLOW_DEMO_SECRETS" == "true" ]]; then
      # В demo-режиме битый override не должен ломать bootstrap; значение не печатаем, там могут быть секреты.
      echo "TF_VAR_app_secret_overrides задан, но не является JSON object<object>. В demo-режиме он будет проигнорирован." >&2
      APP_SECRET_OVERRIDE_ARGS+=("-var=app_secret_overrides={}")
    else
      echo "TF_VAR_app_secret_overrides должен быть JSON object<object>. Исправьте значение или временно включите ALLOW_INSECURE_DEMO_SECRETS=true." >&2
      exit 1
    fi
  fi
elif [[ "$ALLOW_DEMO_SECRETS" == "true" ]]; then
  APP_SECRET_OVERRIDE_ARGS+=("-var=app_secret_overrides={}")
fi

TOKEN_REVIEWER_JWT=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get secret vault-auth-token -o json | jq -r '.data.token | @base64d')
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" get secret vault-auth-token -o json | jq -r '.data["ca.crt"] | @base64d' > "$KUBE_CA_FILE"
KUBERNETES_HOST=$(kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw -o jsonpath='{.clusters[0].cluster.server}')
VAULT_TOKEN=$(jq -r '.root_token' "$VAULT_KEYS_FILE")

kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$VAULT_NAMESPACE" port-forward --address 127.0.0.1 svc/vault "${VAULT_LOCAL_PORT}:8200" > "$PORT_FORWARD_LOG" 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true' EXIT

VAULT_READY=false
for _ in {1..30}; do
  if ! kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1; then
    echo "Vault port-forward завершился раньше времени. Лог: $PORT_FORWARD_LOG" >&2
    tail -50 "$PORT_FORWARD_LOG" >&2 || true
    exit 1
  fi

  if curl -fsS "http://127.0.0.1:${VAULT_LOCAL_PORT}/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204" >/dev/null 2>&1; then
    VAULT_READY=true
    break
  fi
  sleep 2
done

if [[ "$VAULT_READY" != "true" ]]; then
  echo "Vault API не стал доступен через port-forward. Лог: $PORT_FORWARD_LOG" >&2
  exit 1
fi

export TF_VAR_vault_addr="http://127.0.0.1:${VAULT_LOCAL_PORT}"
export TF_VAR_vault_token="$VAULT_TOKEN"
export TF_VAR_token_reviewer_jwt="$TOKEN_REVIEWER_JWT"
export TF_VAR_allow_demo_secrets="$ALLOW_DEMO_SECRETS"

terraform -chdir=terraform/vault init -input=false
terraform -chdir=terraform/vault apply \
  -input=false \
  -auto-approve \
  -var="kubernetes_host=${KUBERNETES_HOST}" \
  -var="kubernetes_ca_cert_path=../../${KUBE_CA_FILE}" \
  -var="allow_demo_secrets=${ALLOW_DEMO_SECRETS}" \
  "${APP_SECRET_OVERRIDE_ARGS[@]}"
