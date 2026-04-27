#!/usr/bin/env bash
set -euo pipefail
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes || true
kubectl -n ingress-nginx get pods
kubectl -n observability get pods
kubectl -n security get pods
