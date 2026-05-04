#!/usr/bin/env bash
# Скрипт устанавливает Vault через Helm release, которым управляет Terraform.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
KUBECONFIG_PATH=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}
ROOT_DIR=$(pwd)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}
VAULT_HOST=${VAULT_HOST:-vault.${APP_DOMAIN}}

source "${SCRIPT_DIR}/lib/public-tls.sh"

[[ -f "$KUBECONFIG_PATH" ]] || { echo "Не найден kubeconfig: $KUBECONFIG_PATH" >&2; exit 1; }

export KUBECONFIG="$KUBECONFIG_PATH"
validate_public_tls_inputs
require_prod_cluster_issuer

# Vault хранит Raft-данные в PVC, поэтому перед установкой Helm release гарантируем наличие local-path provisioner.
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f kubernetes/bootstrap/local-path-storage.yaml
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f kubernetes/bootstrap/storageclass.yaml
kubectl --kubeconfig "$KUBECONFIG_PATH" -n local-path-storage rollout status deployment/local-path-provisioner --timeout=300s
delete_tls_artifact_if_not_prod security vault-tls vault-tls

terraform -chdir=terraform/platform init -input=false
terraform -chdir=terraform/platform apply \
  -input=false \
  -auto-approve \
  -var="kubeconfig_path=${ROOT_DIR}/${KUBECONFIG_PATH}" \
  -var="vault_host=${VAULT_HOST}" \
  -var="vault_tls_cluster_issuer=${TLS_CLUSTER_ISSUER}"

PENDING_SERVER_PODS=$(
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get pods \
    -l app.kubernetes.io/name=vault,component=server \
    --field-selector=status.phase=Pending \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
)

while IFS= read -r pod; do
  [[ -n "$pod" ]] || continue
  POD_TOLERATION_KEYS=$(
    kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get "pod/${pod}" \
      -o jsonpath='{range .spec.tolerations[*]}{.key}{"\n"}{end}'
  )
  if ! grep -qx "node-role.kubernetes.io/control-plane" <<< "$POD_TOLERATION_KEYS"; then
    # Vault StatefulSet обновляется через OnDelete; ожидающий Pod со старым шаблоном нужно пересоздать.
    kubectl --kubeconfig "$KUBECONFIG_PATH" -n security delete "pod/${pod}" --wait=false
  fi
done <<< "$PENDING_SERVER_PODS"

VAULT_REPLICAS=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get statefulset vault -o jsonpath='{.spec.replicas}')

for ((i = 0; i < VAULT_REPLICAS; i++)); do
  pod="vault-${i}"
  for ((attempt = 1; attempt <= 60; attempt++)); do
    if kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get "pod/${pod}" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  # До init/unseal серверные Pod'ы Vault не обязаны быть Ready, но обязаны запланироваться и привязать PVC.
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n security wait --for=condition=PodScheduled "pod/${pod}" --timeout=300s
done

kubectl --kubeconfig "$KUBECONFIG_PATH" -n security get pods,svc,pvc
wait_certificate_ready security vault-tls 1200s
