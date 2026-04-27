#!/usr/bin/env bash
# Проверяет ожидаемые ограничения RBAC для прикладных ServiceAccount.
set -euo pipefail

can_i_yes() {
  local title="$1"
  shift
  echo "RBAC allow expected: $title"
  kubectl auth can-i "$@" | grep -qx "yes"
}

can_i_no() {
  local title="$1"
  shift
  echo "RBAC deny expected: $title"
  kubectl auth can-i "$@" | grep -qx "no"
}

kubectl -n app get role app-deployer app-reader
kubectl -n app get rolebinding app-deployer-binding

can_i_yes "app:default can create deployments" \
  create deployments.apps \
  --as=system:serviceaccount:app:default \
  -n app

can_i_yes "app:default can patch services" \
  patch services \
  --as=system:serviceaccount:app:default \
  -n app

can_i_no "app:default cannot delete secrets" \
  delete secrets \
  --as=system:serviceaccount:app:default \
  -n app

can_i_no "app:default cannot read cluster nodes" \
  list nodes \
  --as=system:serviceaccount:app:default

for service_account in api gateway frontend; do
  can_i_no "app:${service_account} cannot read app secrets" \
    get secrets \
    --as="system:serviceaccount:app:${service_account}" \
    -n app

  can_i_no "app:${service_account} cannot create deployments" \
    create deployments.apps \
    --as="system:serviceaccount:app:${service_account}" \
    -n app
done

