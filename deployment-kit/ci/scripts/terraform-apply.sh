#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
TF_DIR=terraform/vm
ART=.artifacts/${ENV_NAME}

mkdir -p "${ART}" ansible/inventory/generated
terraform -chdir="${TF_DIR}" init -input=false
terraform -chdir="${TF_DIR}" apply   -input=false   -auto-approve   -var-file="../../environments/${ENV_NAME}/terraform.tfvars"

terraform -chdir="${TF_DIR}" output -raw inventory_yaml > ansible/inventory/generated/hosts.yml
terraform -chdir="${TF_DIR}" output -json > "${ART}/terraform-outputs.json"

cp "environments/${ENV_NAME}/ansible-vars.yml" "${ART}/ansible-vars.yml"
cp "environments/${ENV_NAME}/kubeadm-config.yml" "${ART}/kubeadm-config.yml"
