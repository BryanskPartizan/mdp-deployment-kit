#!/usr/bin/env bash
# Проверяет готовность GitLab как devops-компонента платформы.
set -euo pipefail

ENV_NAME=${1:-vm-dev}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE:-devops}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
GITLAB_HOST=${GITLAB_HOST:-gitlab.${APP_DOMAIN}}
GITLAB_REGISTRY_HOST=${GITLAB_REGISTRY_HOST:-registry.${APP_DOMAIN}}
ARTIFACTS_DIR=.artifacts/${ENV_NAME}
TERRAFORM_OUTPUTS=${ARTIFACTS_DIR}/terraform-outputs.json

kubectl get namespace "$GITLAB_NAMESPACE"
kubectl get namespace ci
kubectl -n "$GITLAB_NAMESPACE" get secret gitlab-root-password
kubectl -n "$GITLAB_NAMESPACE" get ingress
kubectl -n "$GITLAB_NAMESPACE" get pvc
kubectl -n observability get servicemonitor deployment-kit-gitlab-probes

kubectl -n "$GITLAB_NAMESPACE" get deploy -o name | while read -r deployment; do
  [[ -n "$deployment" ]] || continue
  kubectl -n "$GITLAB_NAMESPACE" rollout status "$deployment" --timeout=900s
done

kubectl -n "$GITLAB_NAMESPACE" get statefulset -o name | while read -r statefulset; do
  [[ -n "$statefulset" ]] || continue
  kubectl -n "$GITLAB_NAMESPACE" rollout status "$statefulset" --timeout=900s
done

if [[ -f "$TERRAFORM_OUTPUTS" ]] && command -v jq >/dev/null && command -v curl >/dev/null; then
  INGRESS_IP=$(jq -r '.ingress_external_ip.value // empty' "$TERRAFORM_OUTPUTS")

  if [[ -n "$INGRESS_IP" ]]; then
    GITLAB_CODE=$(curl -kfsS -o /dev/null -w '%{http_code}' --resolve "${GITLAB_HOST}:443:${INGRESS_IP}" "https://${GITLAB_HOST}/users/sign_in")
    [[ "$GITLAB_CODE" =~ ^(200|302)$ ]] || { echo "Неожиданный HTTP code GitLab: $GITLAB_CODE" >&2; exit 1; }

    REGISTRY_CODE=$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "${GITLAB_REGISTRY_HOST}:443:${INGRESS_IP}" "https://${GITLAB_REGISTRY_HOST}/v2/")
    [[ "$REGISTRY_CODE" =~ ^(200|401)$ ]] || { echo "Неожиданный HTTP code registry: $REGISTRY_CODE" >&2; exit 1; }
  fi
fi
