#!/usr/bin/env bash
# Скрипт автоматизирует отдельную стадию развертывания deployment kit.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
TF_DIR=terraform/vm
ART=.artifacts/${ENV_NAME}

mkdir -p "${ART}"
terraform -chdir="${TF_DIR}" init -input=false
terraform -chdir="${TF_DIR}" plan   -var-file="../../environments/${ENV_NAME}/terraform.tfvars"   -out="../../${ART}/tfplan"
