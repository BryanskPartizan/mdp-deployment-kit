#!/usr/bin/env bash
# Проверяет ожидаемые ограничения RBAC для прикладных ServiceAccount.
set -euo pipefail

can_i_yes() {
  local title="$1"
  local result
  shift
  echo "RBAC allow expected: $title"
  result=$(kubectl auth can-i "$@")
  [[ "$result" == "yes" ]]
}

can_i_no() {
  local title="$1"
  local result
  local exit_code
  shift
  echo "RBAC deny expected: $title"
  set +e
  result=$(kubectl auth can-i "$@")
  exit_code=$?
  set -e
  [[ "$result" == "no" && "$exit_code" -ne 0 ]]
}

kubectl -n app get role app-deployer app-reader
kubectl -n app get serviceaccount app-deployer
kubectl -n app get rolebinding app-deployer-binding

can_i_yes "app:app-deployer can create deployments" \
  create deployments.apps \
  --as=system:serviceaccount:app:app-deployer \
  -n app

can_i_yes "app:app-deployer can patch services" \
  patch services \
  --as=system:serviceaccount:app:app-deployer \
  -n app

can_i_no "app:app-deployer cannot delete secrets" \
  delete secrets \
  --as=system:serviceaccount:app:app-deployer \
  -n app

can_i_no "app:default cannot read cluster nodes" \
  list nodes \
  --as=system:serviceaccount:app:default

can_i_no "app:default cannot create deployments" \
  create deployments.apps \
  --as=system:serviceaccount:app:default \
  -n app

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
