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

wait_http_code() {
  local name="$1"
  local host="$2"
  local path="$3"
  local expected_regex="$4"
  local ingress_ip="$5"
  local code=""

  for attempt in {1..12}; do
    code=$(curl -ksS -o /dev/null -w '%{http_code}' \
      --resolve "${host}:443:${ingress_ip}" \
      "https://${host}${path}" || true)

    if [[ "$code" =~ $expected_regex ]]; then
      echo "${name}: https://${host}${path} -> ${code}"
      return 0
    fi

    sleep 5
  done

  echo "${name}: неожиданный HTTP code ${code} для https://${host}${path}" >&2
  return 1
}

check_lets_encrypt_certificate() {
  local host="$1"
  local issuer=""

  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl не найден; TLS issuer для ${host} не проверен."
    return 0
  fi

  issuer=$(openssl s_client -connect "${host}:443" -servername "$host" -showcerts </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null || true)

  echo "${host}: ${issuer:-issuer не получен}"
  [[ "$issuer" == *"Let's Encrypt"* ]] || {
    echo "Сертификат ${host} выпущен не Let's Encrypt." >&2
    return 1
  }
}

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
    wait_http_code "GitLab web" "$GITLAB_HOST" "/users/sign_in" "^(200|302)$" "$INGRESS_IP"
    wait_http_code "GitLab registry" "$GITLAB_REGISTRY_HOST" "/v2/" "^(200|401)$" "$INGRESS_IP"
    check_lets_encrypt_certificate "$GITLAB_HOST"
    check_lets_encrypt_certificate "$GITLAB_REGISTRY_HOST"
  fi
fi
