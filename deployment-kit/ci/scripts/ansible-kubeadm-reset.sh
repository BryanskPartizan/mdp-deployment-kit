#!/usr/bin/env bash
# Скрипт очищает kubeadm-состояние на существующих VM без удаления Terraform-инфраструктуры.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
export ENV="${ENV_NAME}"
export ANSIBLE_CONFIG=ansible/ansible.cfg
# Локальный temp держим внутри проекта, чтобы reset не зависел от прав на ~/.ansible.
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-.ansible/tmp}"
CLUSTER_ARTIFACTS_DIR="${CLUSTER_ARTIFACTS_DIR:-${PWD}/.artifacts/${ENV_NAME}}"
CLUSTER_ARTIFACTS_DIR_JSON="${CLUSTER_ARTIFACTS_DIR//\\/\\\\}"
CLUSTER_ARTIFACTS_DIR_JSON="${CLUSTER_ARTIFACTS_DIR_JSON//\"/\\\"}"
EXTRA_VARS_JSON="{\"cluster_artifacts_dir\":\"${CLUSTER_ARTIFACTS_DIR_JSON}\"}"
mkdir -p "$ANSIBLE_LOCAL_TEMP"
mkdir -p "$CLUSTER_ARTIFACTS_DIR"

if [[ "${CONFIRM_RESET:-}" != "$ENV_NAME" ]]; then
  echo "Reset Kubernetes требует подтверждения: CONFIRM_RESET=${ENV_NAME} make kubeadm-reset ENV=${ENV_NAME}" >&2
  exit 1
fi

[[ -f ansible/inventory/generated/hosts.yml ]] || { echo "Сгенерированный inventory не найден. Сначала выполните terraform apply." >&2; exit 1; }

SSH_PRIVATE_KEY_PATH=""
if [[ -z "${ANSIBLE_PRIVATE_KEY_FILE:-}" ]] && ! grep -q "ansible_ssh_private_key_file" ansible/inventory/generated/hosts.yml; then
  SSH_PUBLIC_KEY_PATH="$(grep -E '^[[:space:]]*ssh_public_key_path[[:space:]]*=' "environments/${ENV_NAME}/terraform.tfvars" | awk -F'"' '{print $2}')"
  if [[ -n "$SSH_PUBLIC_KEY_PATH" && "$SSH_PUBLIC_KEY_PATH" == *.pub ]]; then
    SSH_PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_PATH%.pub}"
  fi
fi

if [[ -n "$SSH_PRIVATE_KEY_PATH" && -f "$SSH_PRIVATE_KEY_PATH" ]]; then
  # Старые inventory, созданные до добавления ansible_ssh_private_key_file, всё ещё можно использовать.
  ansible-playbook --private-key "$SSH_PRIVATE_KEY_PATH" -i ansible/inventory/generated/hosts.yml ansible/playbooks/reset-kubeadm.yml -e @"environments/${ENV_NAME}/ansible-vars.yml" -e "$EXTRA_VARS_JSON"
else
  ansible-playbook -i ansible/inventory/generated/hosts.yml ansible/playbooks/reset-kubeadm.yml -e @"environments/${ENV_NAME}/ansible-vars.yml" -e "$EXTRA_VARS_JSON"
fi
