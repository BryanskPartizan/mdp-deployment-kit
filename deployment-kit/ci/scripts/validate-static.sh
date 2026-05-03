#!/usr/bin/env bash
# Скрипт выполняет локальные статические проверки deployment-kit без доступа к реальному кластеру.
set -euo pipefail

terraform fmt -check -recursive terraform

# Проверяем синтаксис shell-скриптов, чтобы CI падал до запуска долгих стадий.
find ci/scripts tests -name '*.sh' -print0 | xargs -0 bash -n

# Проверяем синтаксис JS-заглушек, если локально доступен Node.js.
if command -v node >/dev/null 2>&1; then
  find apps -name '*.js' -print0 | xargs -0 -n1 node --check
else
  echo "node не найден, проверка JS-заглушек пропущена."
fi

# Приватный домен стенда по умолчанию должен оставаться mdp; старые *.local шаблоны не должны возвращаться.
if command -v rg >/dev/null 2>&1; then
  if rg -n "lab\\.local|stage\\.local|aws-stage\\.local" README.md docs kubernetes ci tests environments terraform ansible; then
    echo "Найдены устаревшие приватные домены. Используйте mdp или APP_DOMAIN/domain_name overrides." >&2
    exit 1
  fi
  if rg -n "\\*join-command|join-command\\.sh" ci/templates; then
    echo "Join-команды не должны публиковаться как CI artifacts." >&2
    exit 1
  fi
  if rg -n "cat /vault/secrets" tests ci --glob '!ci/scripts/validate-static.sh'; then
    echo "Тесты не должны печатать содержимое Vault secret files." >&2
    exit 1
  fi
  if rg -n --multiline "egress:\\n\\s+- \\{\\}" kubernetes/apps kubernetes/security; then
    echo "Найдены NetworkPolicy с полностью открытым egress." >&2
    exit 1
  fi
  if rg -n "delete secret (postgres-auth|gitlab-root-password).*--ignore-not-found" ci/scripts; then
    echo "Секреты PostgreSQL/GitLab нельзя silently пересоздавать в обычном deploy path." >&2
    exit 1
  fi
fi

template_chart_if_available() {
  local release_name="$1"
  local chart_ref="$2"
  local chart_version="$3"
  shift 3

  if helm show chart "$chart_ref" --version "$chart_version" >/dev/null 2>&1; then
    helm template "$release_name" "$chart_ref" --version "$chart_version" "$@" >/dev/null
  else
    echo "Chart ${chart_ref} ${chart_version} недоступен локально, Helm template ${release_name} пропущен."
  fi
}

# Проверяем рендеринг Helm chart приложений для dev-профиля.
for app in api gateway frontend; do
  helm template "$app" "kubernetes/apps/${app}" \
    -f "kubernetes/apps/${app}/values.yaml" \
    -f "kubernetes/apps/${app}/values-dev.yaml" >/dev/null
done

# Проверяем JSON dashboards, если на машине доступен Ruby с YAML/JSON из стандартной библиотеки.
if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -rjson -e 'YAML.load_file("kubernetes/observability/grafana-dashboards.yaml")["data"].each { |_name, body| JSON.parse(body) }'
else
  echo "ruby не найден, проверка JSON Grafana dashboards пропущена."
fi

# Проверяем platform charts при доступных Helm repositories/cache.
template_chart_if_available ingress-nginx ingress-nginx/ingress-nginx "${INGRESS_NGINX_CHART_VERSION:-4.15.1}" \
  -f kubernetes/base/ingress-nginx-values.yaml
template_chart_if_available cert-manager oci://quay.io/jetstack/charts/cert-manager "${CERT_MANAGER_VERSION:-v1.19.5}" \
  -f kubernetes/base/cert-manager-values.yaml
template_chart_if_available metrics-server metrics-server/metrics-server "${METRICS_SERVER_CHART_VERSION:-3.13.0}" \
  -f kubernetes/base/metrics-server-values.yaml
template_chart_if_available kube-prometheus-stack prometheus-community/kube-prometheus-stack "${PROMETHEUS_STACK_CHART_VERSION:-84.3.0}" \
  -f kubernetes/base/prometheus-stack-values.yaml
template_chart_if_available loki grafana/loki "${LOKI_CHART_VERSION:-7.0.0}" \
  -f kubernetes/base/loki-values.yaml
template_chart_if_available blackbox-exporter prometheus-community/prometheus-blackbox-exporter "${BLACKBOX_EXPORTER_CHART_VERSION:-11.9.1}" \
  --namespace observability \
  -f kubernetes/base/blackbox-exporter-values.yaml
template_chart_if_available alloy grafana/alloy "${ALLOY_CHART_VERSION:-1.8.0}" \
  --namespace observability \
  -f kubernetes/base/alloy-values.yaml
template_chart_if_available headlamp headlamp/headlamp "${HEADLAMP_CHART_VERSION:-0.41.0}" \
  --namespace k8s-admin \
  -f kubernetes/base/headlamp-values.yaml

# Проверяем stateful зависимости приложений.
template_chart_if_available postgres bitnami/postgresql "${POSTGRES_CHART_VERSION:-18.6.2}" \
  -f kubernetes/apps/postgres/values.yaml \
  -f kubernetes/apps/postgres/values-dev.yaml
template_chart_if_available redis bitnami/redis "${REDIS_CHART_VERSION:-25.4.1}" \
  -f kubernetes/apps/redis/values.yaml \
  -f kubernetes/apps/redis/values-dev.yaml

# GitLab chart тяжёлый, поэтому рендерим его только если chart доступен локально или через configured repo.
template_chart_if_available gitlab gitlab/gitlab "${GITLAB_CHART_VERSION:-9.11.1}" \
  --namespace devops \
  -f kubernetes/platform/gitlab/values.yaml \
  -f kubernetes/platform/gitlab/values-dev.yaml

# Если Ansible установлен на машине проверки, валидируем синтаксис playbook'ов.
if command -v ansible-playbook >/dev/null 2>&1; then
  export ANSIBLE_CONFIG=ansible/ansible.cfg
  # Локальный temp нужен для sandbox/CI, где домашний каталог runner'а может быть read-only.
  export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-.ansible/tmp}"
  mkdir -p "$ANSIBLE_LOCAL_TEMP"
  ansible-playbook -i ansible/inventory/static/hosts.example.yml ansible/playbooks/site.yml --syntax-check
  ansible-playbook -i ansible/inventory/static/hosts.example.yml ansible/playbooks/reset-kubeadm.yml --syntax-check
else
  echo "ansible-playbook не найден, Ansible syntax-check пропущен."
fi

# Terraform validate требует предварительного init, но не требует реальных YC credentials.
for dir in terraform/vm terraform/edge terraform/platform terraform/vault; do
  if [[ ! -d "$dir/.terraform/providers" ]]; then
    terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  else
    echo "Terraform providers уже установлены для $dir, init пропущен."
  fi
  terraform -chdir="$dir" validate
done
