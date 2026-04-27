#!/usr/bin/env bash
# Проверяет доступность HA control plane без искусственного отказа узлов.
set -euo pipefail

MIN_CONTROL_PLANES=${MIN_CONTROL_PLANES:-3}

kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'

READY_CONTROL_PLANES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{range .items[?(@.status.conditions[?(@.type=="Ready")].status=="True")]}{.metadata.name}{"\n"}{end}' | sed '/^$/d' | wc -l | tr -d ' ')

if [[ "$READY_CONTROL_PLANES" -lt "$MIN_CONTROL_PLANES" ]]; then
  echo "Недостаточно Ready control-plane узлов: ${READY_CONTROL_PLANES}, минимум ${MIN_CONTROL_PLANES}" >&2
  exit 1
fi

kubectl -n kube-system get pods -l component=etcd
kubectl -n kube-system get pods -l component=kube-apiserver
kubectl -n kube-system get pods -l component=kube-controller-manager
kubectl -n kube-system get pods -l component=kube-scheduler

