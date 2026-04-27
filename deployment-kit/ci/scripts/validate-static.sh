#!/usr/bin/env bash
# Скрипт выполняет локальные статические проверки deployment-kit без доступа к реальному кластеру.
set -euo pipefail

terraform fmt -check -recursive terraform

# Проверяем синтаксис shell-скриптов, чтобы CI падал до запуска долгих стадий.
find ci/scripts tests -name '*.sh' -print0 | xargs -0 bash -n

# Проверяем рендеринг Helm chart приложений для dev-профиля.
for app in api gateway frontend; do
  helm template "$app" "kubernetes/apps/${app}" \
    -f "kubernetes/apps/${app}/values.yaml" \
    -f "kubernetes/apps/${app}/values-dev.yaml" >/dev/null
done

# Если Ansible установлен на машине проверки, валидируем синтаксис playbook'ов.
if command -v ansible-playbook >/dev/null 2>&1; then
  export ANSIBLE_CONFIG=ansible/ansible.cfg
  ansible-playbook -i ansible/inventory/static/hosts.example.yml ansible/playbooks/site.yml --syntax-check
  ansible-playbook -i ansible/inventory/static/hosts.example.yml ansible/playbooks/reset-kubeadm.yml --syntax-check
else
  echo "ansible-playbook не найден, Ansible syntax-check пропущен."
fi

# Terraform validate требует предварительного init, но не требует реальных YC credentials.
for dir in terraform/vm terraform/platform terraform/vault; do
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  terraform -chdir="$dir" validate
done
