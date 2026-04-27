#!/usr/bin/env bash
set -euo pipefail

# Проверяем базовую готовность кластера и платформенных namespace.
kubectl get nodes -o wide
kubectl wait --for=condition=Ready nodes --all --timeout=300s

kubectl get pods -A

# Любой Pod вне Running/Completed считается ошибкой smoke-проверки.
kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" { print; failed=1 } END { exit failed }'

kubectl top nodes || true
kubectl -n ingress-nginx get pods
kubectl -n observability get pods
kubectl -n security get pods
