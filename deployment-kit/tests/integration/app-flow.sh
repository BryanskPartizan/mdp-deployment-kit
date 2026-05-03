#!/usr/bin/env bash
# Проверяет базовый интеграционный путь: Stateful-сервисы, Deployments и HTTP health endpoints.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../lib/k8s-probe.sh"

require_command kubectl

wait_rollout app statefulset postgres-postgresql
wait_rollout app statefulset redis-master
wait_rollout app deployment api
wait_rollout app deployment gateway
wait_rollout app deployment frontend

for service_name in api gateway frontend postgres-postgresql redis-master; do
  echo "Проверка Endpoints для ${service_name}"
  kubectl -n app get endpoints "$service_name" -o jsonpath='{.subsets[0].addresses[0].ip}' | grep -E '.+'
  echo
done

kubectl -n observability get servicemonitor deployment-kit-app-probes

expect_success "gateway sees api /health" \
  app \
  "app.kubernetes.io/name=gateway,dk-test=integration" \
  "curl -fsS --connect-timeout 5 http://api.app.svc.cluster.local:8081/health"

expect_success "ingress namespace sees gateway /health" \
  ingress-nginx \
  "dk-test=integration" \
  "curl -fsS --connect-timeout 5 http://gateway.app.svc.cluster.local:8080/health"

expect_success "ingress namespace sees frontend /health" \
  ingress-nginx \
  "dk-test=integration" \
  "curl -fsS --connect-timeout 5 http://frontend.app.svc.cluster.local:8080/health"

expect_success "gateway creates and reads demo lead" \
  app \
  "app.kubernetes.io/name=gateway,dk-test=integration" \
  "created=\$(curl -fsS -H 'content-type: application/json' -d '{\"name\":\"Gateway Test Lead\",\"company\":\"Deployment Kit\",\"status\":\"qualified\",\"budget\":50000}' http://gateway.app.svc.cluster.local:8080/leads); id=\$(printf '%s' \"\$created\" | sed -n 's/.*\"id\":\"\\([^\"]*\\)\".*/\\1/p'); test -n \"\$id\"; curl -fsS http://gateway.app.svc.cluster.local:8080/leads/\"\$id\" | grep -q 'Gateway Test Lead'"

expect_success "frontend proxy creates and reads demo lead" \
  ingress-nginx \
  "dk-test=integration" \
  "created=\$(curl -fsS -H 'content-type: application/json' -d '{\"name\":\"Frontend Test Lead\",\"company\":\"Deployment Kit\",\"status\":\"contacted\",\"budget\":25000}' http://frontend.app.svc.cluster.local:8080/leads); id=\$(printf '%s' \"\$created\" | sed -n 's/.*\"id\":\"\\([^\"]*\\)\".*/\\1/p'); test -n \"\$id\"; curl -fsS http://frontend.app.svc.cluster.local:8080/leads/\"\$id\" | grep -q 'Frontend Test Lead'"
