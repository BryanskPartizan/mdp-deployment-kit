#!/usr/bin/env bash
# Проверяет, что NetworkPolicy разрешают только ожидаемые маршруты.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../lib/k8s-probe.sh"

require_command kubectl

kubectl -n app get networkpolicy \
  default-deny \
  allow-gateway-to-api \
  allow-api-to-postgres \
  allow-api-to-redis \
  allow-observability-scrape \
  allow-observability-to-datastores

expect_failure "unlabeled app pod -> api:8081" \
  app \
  "dk-test=security" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 api.app.svc.cluster.local 8081"

expect_failure "frontend -> postgres:5432" \
  app \
  "app.kubernetes.io/name=frontend,dk-test=security" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 postgres-postgresql.app.svc.cluster.local 5432"

expect_failure "gateway -> redis:6379" \
  app \
  "app.kubernetes.io/name=gateway,dk-test=security" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 redis-master.app.svc.cluster.local 6379"

expect_failure "default namespace -> frontend:8080" \
  default \
  "dk-test=security" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 frontend.app.svc.cluster.local 8080"
