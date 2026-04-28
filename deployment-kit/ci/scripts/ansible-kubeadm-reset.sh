#!/usr/bin/env bash
# Скрипт очищает kubeadm-состояние на существующих VM без удаления Terraform-инфраструктуры.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
export ENV="${ENV_NAME}"
export ANSIBLE_CONFIG=ansible/ansible.cfg
# Локальный temp держим внутри проекта, чтобы reset не зависел от прав на ~/.ansible.
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-.ansible/tmp}"
mkdir -p "$ANSIBLE_LOCAL_TEMP"

if [[ "${CONFIRM_RESET:-}" != "$ENV_NAME" ]]; then
  echo "Reset Kubernetes требует подтверждения: CONFIRM_RESET=${ENV_NAME} make kubeadm-reset ENV=${ENV_NAME}" >&2
  exit 1
fi

[[ -f ansible/inventory/generated/hosts.yml ]] || { echo "Сгенерированный inventory не найден. Сначала выполните terraform apply." >&2; exit 1; }
ansible-playbook -i ansible/inventory/generated/hosts.yml ansible/playbooks/reset-kubeadm.yml -e @"environments/${ENV_NAME}/ansible-vars.yml"
