#!/usr/bin/env bash
# Скрипт создаёт GitLab-проект deployment-kit, настраивает CI variables и при возможности пушит текущую ветку.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
APP_NAMESPACE=${APP_NAMESPACE:-app}
TLS_CLUSTER_ISSUER=${TLS_CLUSTER_ISSUER:-letsencrypt-prod}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-${REGISTRY_SERVER:-registry.${APP_DOMAIN}}}
REGISTRY_SERVER=${REGISTRY_SERVER:-${IMAGE_REGISTRY}}
REGISTRY_USER=${REGISTRY_USER:-root}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_ROOT_SECRET=${GITLAB_ROOT_SECRET:-gitlab-root-password}
GITLAB_TOOLBOX_SELECTOR=${GITLAB_TOOLBOX_SELECTOR:-app=toolbox,release=gitlab}
GITLAB_PROJECT_PATH=${GITLAB_PROJECT_PATH:-platform/deployment-kit}
GITLAB_HOST=${GITLAB_HOST:-gitlab.${APP_DOMAIN}}
GITLAB_REMOTE_NAME=${GITLAB_REMOTE_NAME:-gitlab-platform}
GITLAB_PUSH_BRANCH=${GITLAB_PUSH_BRANCH:-main}
PUSH_REPOSITORY=${PUSH_REPOSITORY:-true}
ASKPASS_FILE=""

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Не найден обязательный файл: $path" >&2; exit 1; }
}

find_toolbox_pod() {
  local pod
  pod=$(kubectl -n "$GITLAB_NAMESPACE" get pods \
    -l "$GITLAB_TOOLBOX_SELECTOR" \
    -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $1}')

  if [[ -z "$pod" ]]; then
    pod=$(kubectl -n "$GITLAB_NAMESPACE" get pods \
      -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | tr ' ' '\n' | awk '/gitlab-toolbox/ {print; exit}')
  fi

  if [[ -z "$pod" ]]; then
    echo "Не найден running GitLab toolbox pod в namespace ${GITLAB_NAMESPACE}." >&2
    exit 1
  fi

  printf '%s' "$pod"
}

resolve_registry_password() {
  if [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
    printf '%s' "$REGISTRY_PASSWORD"
    return
  fi

  kubectl -n "$GITLAB_NAMESPACE" get secret "$GITLAB_ROOT_SECRET" -o jsonpath='{.data.password}' | base64 --decode
}

encode_kubeconfig() {
  if [[ -n "${KUBECONFIG_B64:-}" ]]; then
    printf '%s' "$KUBECONFIG_B64"
    return
  fi

  base64 < "$KUBECONFIG" | tr -d '\n'
}

configure_git_remote() {
  local root_password="$1"
  local remote_url="https://${GITLAB_HOST}/${GITLAB_PROJECT_PATH}.git"
  local askpass

  if [[ "$PUSH_REPOSITORY" != "true" ]]; then
    echo "Пуш репозитория пропущен: PUSH_REPOSITORY=${PUSH_REPOSITORY}."
    return
  fi

  require_command git

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "В рабочем дереве есть незакоммиченные изменения; git push отправит только уже созданные commits."
  fi

  if git remote get-url "$GITLAB_REMOTE_NAME" >/dev/null 2>&1; then
    git remote set-url "$GITLAB_REMOTE_NAME" "$remote_url"
  else
    git remote add "$GITLAB_REMOTE_NAME" "$remote_url"
  fi

  askpass=$(mktemp)
  ASKPASS_FILE="$askpass"
  chmod 0700 "$askpass"
  cat > "$askpass" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  *Username*) printf '%s\n' "${GITLAB_USERNAME_FOR_PUSH:-root}" ;;
  *Password*) printf '%s\n' "$GITLAB_ROOT_PASSWORD_FOR_PUSH" ;;
  *) printf '\n' ;;
esac
EOF
  trap 'rm -f "$ASKPASS_FILE" "$RUBY_SCRIPT"' EXIT

  echo "Пуш текущей ветки в ${remote_url} -> ${GITLAB_PUSH_BRANCH}."
  if ! GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS="$askpass" \
    GITLAB_USERNAME_FOR_PUSH="$REGISTRY_USER" \
    GITLAB_ROOT_PASSWORD_FOR_PUSH="$root_password" \
    git push "$GITLAB_REMOTE_NAME" "HEAD:${GITLAB_PUSH_BRANCH}"; then
    echo "git push не выполнился. Проверьте, разрешён ли HTTP Git login для пользователя ${REGISTRY_USER}, либо выполните push с персональным токеном." >&2
    return 1
  fi
}

require_command kubectl
require_file "$KUBECONFIG"

"$(dirname "$0")/prepare-gitlab-registry-projects.sh" "$ENV_NAME"

REGISTRY_PASSWORD_RESOLVED=$(resolve_registry_password)
KUBECONFIG_B64_RESOLVED=$(encode_kubeconfig)
TOOLBOX_POD=$(find_toolbox_pod)

echo "Подготовка GitLab CI project ${GITLAB_PROJECT_PATH} через ${GITLAB_NAMESPACE}/${TOOLBOX_POD}."

RUBY_SCRIPT=$(mktemp)
trap 'rm -f "$RUBY_SCRIPT"' EXIT

cat > "$RUBY_SCRIPT" <<'RUBY'
project_path = ENV.fetch("GITLAB_PROJECT_PATH")
group_path, project_slug = project_path.split("/", 2)
raise "GITLAB_PROJECT_PATH должен иметь вид group/project" unless group_path && project_slug

root = User.find_by_username("root") || User.admins.first
raise "Не найден admin user для настройки GitLab CI" unless root

organization = if defined?(Organizations::Organization)
  Organizations::Organization.default_organization
end

group = Group.find_by_full_path(group_path)
unless group
  group_params = {
    name: group_path,
    path: group_path,
    visibility_level: Gitlab::VisibilityLevel::PRIVATE
  }
  group_params[:organization_id] = organization.id if organization

  result = Groups::CreateService.new(root, group_params).execute
  group = result[:group] || result
  raise "Не удалось создать group #{group_path}: #{group.errors.full_messages.join(", ")}" unless group.persisted?
  puts "Создана GitLab group #{group.full_path}"
else
  puts "GitLab group #{group.full_path} уже существует"
end

project = Project.find_by_full_path(project_path)
unless project
  project = Projects::CreateService.new(root, {
    name: project_slug,
    path: project_slug,
    namespace_id: group.id,
    visibility_level: Gitlab::VisibilityLevel::PRIVATE
  }).execute
  raise "Не удалось создать project #{project_path}: #{project.errors.full_messages.join(", ")}" unless project.persisted?
  puts "Создан GitLab project #{project.full_path}"
else
  puts "GitLab project #{project.full_path} уже существует"
end

project.update!(container_registry_enabled: true)

variables = {
  "ENV" => ENV.fetch("ENV_NAME"),
  "APP_DOMAIN" => ENV.fetch("APP_DOMAIN"),
  "APP_NAMESPACE" => ENV.fetch("APP_NAMESPACE"),
  "TLS_CLUSTER_ISSUER" => ENV.fetch("TLS_CLUSTER_ISSUER"),
  "IMAGE_REGISTRY" => ENV.fetch("IMAGE_REGISTRY"),
  "REGISTRY_SERVER" => ENV.fetch("REGISTRY_SERVER"),
  "REGISTRY_USER" => ENV.fetch("REGISTRY_USER"),
  "REGISTRY_PASSWORD" => ENV.fetch("REGISTRY_PASSWORD_RESOLVED"),
  "KUBECONFIG_B64" => ENV.fetch("KUBECONFIG_B64_RESOLVED"),
  "RUN_INFRA_PIPELINE" => "false"
}

variables.each do |key, value|
  variable = project.variables.find_or_initialize_by(key: key)
  variable.value = value
  variable.variable_type = "env_var" if variable.respond_to?(:variable_type=)
  variable.environment_scope = "*" if variable.respond_to?(:environment_scope=)
  variable.protected = false if variable.respond_to?(:protected=)
  variable.masked = false if variable.respond_to?(:masked=)
  variable.raw = true if variable.respond_to?(:raw=)
  variable.save!
  puts "CI variable #{key} настроена"
end
RUBY

kubectl -n "$GITLAB_NAMESPACE" cp "$RUBY_SCRIPT" "${TOOLBOX_POD}:/tmp/deployment-kit-bootstrap-app-ci.rb" -c toolbox
kubectl -n "$GITLAB_NAMESPACE" exec "$TOOLBOX_POD" -c toolbox -- env \
  GITLAB_PROJECT_PATH="$GITLAB_PROJECT_PATH" \
  ENV_NAME="$ENV_NAME" \
  APP_DOMAIN="$APP_DOMAIN" \
  APP_NAMESPACE="$APP_NAMESPACE" \
  TLS_CLUSTER_ISSUER="$TLS_CLUSTER_ISSUER" \
  IMAGE_REGISTRY="$IMAGE_REGISTRY" \
  REGISTRY_SERVER="$REGISTRY_SERVER" \
  REGISTRY_USER="$REGISTRY_USER" \
  REGISTRY_PASSWORD_RESOLVED="$REGISTRY_PASSWORD_RESOLVED" \
  KUBECONFIG_B64_RESOLVED="$KUBECONFIG_B64_RESOLVED" \
  gitlab-rails runner /tmp/deployment-kit-bootstrap-app-ci.rb

configure_git_remote "$REGISTRY_PASSWORD_RESOLVED"
