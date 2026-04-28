#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
export ENV="${ENV_NAME}"
export ANSIBLE_CONFIG=ansible/ansible.cfg
# Локальный temp держим внутри проекта, чтобы запуск не зависел от прав на ~/.ansible.
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-.ansible/tmp}"
mkdir -p "$ANSIBLE_LOCAL_TEMP"

[[ -f ansible/inventory/generated/hosts.yml ]] || { echo "Сгенерированный inventory не найден. Сначала выполните terraform apply." >&2; exit 1; }
ansible-playbook -i ansible/inventory/generated/hosts.yml ansible/playbooks/site.yml -e @"environments/${ENV_NAME}/ansible-vars.yml"
