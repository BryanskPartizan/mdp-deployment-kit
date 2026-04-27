#!/usr/bin/env bash
# Проверяет полный путь Vault Agent Injector: ServiceAccount -> Vault role -> injected secret file.
set -euo pipefail

TEST_IMAGE=${VAULT_TEST_IMAGE:-busybox:1.36}
POD_NAME=${VAULT_TEST_POD_NAME:-vault-api-secret-probe}

cleanup() {
  kubectl -n app delete pod "$POD_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

cleanup
trap cleanup EXIT

kubectl -n security get statefulset vault
kubectl -n security get deployment vault-agent-injector
kubectl -n security rollout status deployment/vault-agent-injector --timeout=300s
kubectl -n app get serviceaccount api

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: app
  labels:
    app.kubernetes.io/name: api
    dk-test: vault
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/agent-pre-populate-only: "true"
    vault.hashicorp.com/role: "api"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/app/api"
spec:
  restartPolicy: Never
  serviceAccountName: api
  containers:
    - name: probe
      image: ${TEST_IMAGE}
      command:
        - sh
        - -ec
        - |
          for i in \$(seq 1 60); do
            if [ -s /vault/secrets/config ]; then
              cat /vault/secrets/config
              grep -q "DATABASE_URL" /vault/secrets/config
              exit 0
            fi
            sleep 2
          done
          echo "Vault secret file was not injected" >&2
          exit 1
YAML

if ! kubectl -n app wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${POD_NAME}" --timeout=300s; then
  kubectl -n app describe pod "$POD_NAME" || true
  kubectl -n app logs "$POD_NAME" --all-containers=true || true
  exit 1
fi

kubectl -n app logs "$POD_NAME" --all-containers=true

