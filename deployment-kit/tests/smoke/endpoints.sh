#!/usr/bin/env bash
set -euo pipefail

kubectl -n app get svc
kubectl -n app get ingress -o wide
kubectl -n app get networkpolicy
kubectl -n app get pvc
