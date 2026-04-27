#!/usr/bin/env bash
# Проверяет переживание drain worker-узла и возвращает узел в schedulable-состояние.
set -euo pipefail

NODE_NAME=${NODE_NAME:-$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')}
UNCORDON_AFTER=${UNCORDON_AFTER:-true}

if [[ -z "$NODE_NAME" ]]; then
  echo "Не найден worker-узел для drain-теста." >&2
  exit 1
fi

cleanup() {
  if [[ "$UNCORDON_AFTER" == "true" ]]; then
    kubectl uncordon "$NODE_NAME" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

echo "Cordon worker-узла: ${NODE_NAME}"
kubectl cordon "$NODE_NAME"

echo "Drain worker-узла: ${NODE_NAME}"
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force --timeout=10m

kubectl -n app rollout status deployment/api --timeout=300s
kubectl -n app rollout status deployment/gateway --timeout=300s
kubectl -n app rollout status deployment/frontend --timeout=300s
kubectl -n app get pods -o wide

