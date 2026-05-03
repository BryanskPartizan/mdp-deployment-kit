#!/usr/bin/env bash
# Создаёт GitLab group/project paths, в которые deployment-kit публикует demo-образы.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
export KUBECONFIG=${KUBECONFIG:-${ARTIFACTS_DIR}/admin.conf}

GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
GITLAB_TOOLBOX_SELECTOR=${GITLAB_TOOLBOX_SELECTOR:-app=toolbox,release=gitlab}
REGISTRY_GROUP=${REGISTRY_GROUP:-platform}
REGISTRY_PROJECTS=${REGISTRY_PROJECTS:-api,gateway,frontend}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
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

require_command kubectl

TOOLBOX_POD=$(find_toolbox_pod)
echo "Подготовка GitLab registry projects через ${GITLAB_NAMESPACE}/${TOOLBOX_POD}."

RUBY_SCRIPT=$(mktemp)
trap 'rm -f "$RUBY_SCRIPT"' EXIT

cat > "$RUBY_SCRIPT" <<'RUBY'
group_path = ENV.fetch("REGISTRY_GROUP")
project_paths = ENV.fetch("REGISTRY_PROJECTS").split(",").map(&:strip).reject(&:empty?)

root = User.find_by_username("root") || User.admins.first
raise "Не найден admin user для создания GitLab projects" unless root

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

project_paths.each do |project_path|
  full_path = "#{group_path}/#{project_path}"
  project = Project.find_by_full_path(full_path)
  if project
    puts "GitLab project #{full_path} уже существует"
    next
  end

  project = Projects::CreateService.new(root, {
    name: project_path,
    path: project_path,
    namespace_id: group.id,
    visibility_level: Gitlab::VisibilityLevel::PRIVATE
  }).execute

  raise "Не удалось создать project #{full_path}: #{project.errors.full_messages.join(", ")}" unless project.persisted?

  project.update!(container_registry_enabled: true)
  puts "Создан GitLab project #{full_path}"
end
RUBY

kubectl -n "$GITLAB_NAMESPACE" cp "$RUBY_SCRIPT" "${TOOLBOX_POD}:/tmp/deployment-kit-prepare-registry-projects.rb" -c toolbox
kubectl -n "$GITLAB_NAMESPACE" exec "$TOOLBOX_POD" -c toolbox -- env \
  REGISTRY_GROUP="$REGISTRY_GROUP" \
  REGISTRY_PROJECTS="$REGISTRY_PROJECTS" \
  gitlab-rails runner /tmp/deployment-kit-prepare-registry-projects.rb
