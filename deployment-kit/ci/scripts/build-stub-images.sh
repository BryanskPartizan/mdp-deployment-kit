#!/usr/bin/env bash
# Скрипт собирает demo-образы прикладных заглушек и при необходимости публикует их в registry.
set -euo pipefail

APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-${REGISTRY_SERVER:-registry.${APP_DOMAIN}}}
IMAGE_TAG=${APP_IMAGE_TAG:-0.2.0}
PUSH_IMAGES=${PUSH_IMAGES:-false}
IMAGE_PLATFORM=${IMAGE_PLATFORM:-linux/amd64}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
}

require_command docker

for app in api gateway frontend; do
  image="${IMAGE_REGISTRY}/platform/${app}:${IMAGE_TAG}"
  if [[ "$PUSH_IMAGES" == "true" ]]; then
    echo "Сборка и публикация ${image} для ${IMAGE_PLATFORM}"
    docker buildx build \
      --platform "$IMAGE_PLATFORM" \
      -f "apps/${app}/Dockerfile" \
      -t "$image" \
      --push \
      apps
  else
    echo "Сборка ${image} для локальной проверки"
    docker build \
      -f "apps/${app}/Dockerfile" \
      -t "$image" \
      apps
  fi
done
