#!/usr/bin/env bash
# Проверяет разрешённые сетевые маршруты внутри кластера и через ingress-контур.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../lib/k8s-probe.sh"

require_command kubectl

kubectl -n app get svc api gateway frontend postgres-postgresql redis-master
kubectl -n ingress-nginx get svc

expect_success "DNS Kubernetes service discovery" \
  app \
  "app.kubernetes.io/name=api,dk-test=network" \
  "dig +short kubernetes.default.svc.cluster.local && dig +short api.app.svc.cluster.local"

expect_success "gateway -> api:8081" \
  app \
  "app.kubernetes.io/name=gateway,dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 api.app.svc.cluster.local 8081"

expect_success "frontend -> gateway:8080" \
  app \
  "app.kubernetes.io/name=frontend,dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 gateway.app.svc.cluster.local 8080"

expect_success "api -> postgres:5432" \
  app \
  "app.kubernetes.io/name=api,dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 postgres-postgresql.app.svc.cluster.local 5432"

expect_success "api -> redis:6379" \
  app \
  "app.kubernetes.io/name=api,dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 redis-master.app.svc.cluster.local 6379"

expect_success "ingress namespace -> frontend:8080" \
  ingress-nginx \
  "dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 frontend.app.svc.cluster.local 8080"

expect_success "ingress namespace -> gateway:8080" \
  ingress-nginx \
  "dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 gateway.app.svc.cluster.local 8080"

expect_success "observability namespace -> api health port" \
  observability \
  "dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 api.app.svc.cluster.local 8081"

expect_success "observability namespace -> postgres tcp probe" \
  observability \
  "dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 postgres-postgresql.app.svc.cluster.local 5432"

expect_success "observability namespace -> redis tcp probe" \
  observability \
  "dk-test=network" \
  "timeout ${TEST_COMMAND_TIMEOUT} nc -zvw3 redis-master.app.svc.cluster.local 6379"
