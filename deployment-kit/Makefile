SHELL := /bin/bash
ENV ?= vm-dev
ARTIFACTS_DIR ?= .artifacts/$(ENV)
KUBECONFIG ?= $(ARTIFACTS_DIR)/admin.conf

export KUBECONFIG

.PHONY: help validate infra-plan infra-apply infra-destroy destroy edge-plan edge-apply edge-destroy kubeadm-bootstrap kubeadm-reset deploy-vault vault-init vault-token vault-admin-token vault-configure deploy-platform deploy-gitlab prepare-gitlab-registry-projects bootstrap-gitlab-app-ci deploy-app-charts deploy-apps docker-registry-login build-stub-images test-stubs test-smoke test-network test-security test-integration test-storage test-gitlab test-resilience test-all test-load test-fail-node render-inventory package

help:
	@echo "Targets: validate infra-plan infra-apply infra-destroy edge-plan edge-apply edge-destroy kubeadm-bootstrap kubeadm-reset deploy-vault vault-init vault-token vault-admin-token vault-configure deploy-platform deploy-gitlab prepare-gitlab-registry-projects bootstrap-gitlab-app-ci deploy-app-charts deploy-apps docker-registry-login build-stub-images test-stubs test-smoke test-network test-security test-integration test-storage test-gitlab test-resilience test-all test-load test-fail-node package"

validate:
	./ci/scripts/validate-static.sh

infra-plan:
	./ci/scripts/terraform-plan.sh $(ENV)

infra-apply:
	./ci/scripts/terraform-apply.sh $(ENV)

infra-destroy:
	./ci/scripts/terraform-destroy.sh $(ENV)

destroy: infra-destroy

edge-plan:
	./ci/scripts/edge-plan.sh $(ENV)

edge-apply:
	./ci/scripts/edge-apply.sh $(ENV)

edge-destroy:
	./ci/scripts/edge-destroy.sh $(ENV)

kubeadm-bootstrap:
	./ci/scripts/ansible-kubeadm-bootstrap.sh $(ENV)

kubeadm-reset:
	./ci/scripts/ansible-kubeadm-reset.sh $(ENV)

deploy-vault:
	./ci/scripts/deploy-vault.sh $(ENV)

vault-init:
	./ci/scripts/vault-init.sh $(ENV)

vault-token:
	./ci/scripts/vault-token.sh $(ENV) show-root

vault-admin-token:
	./ci/scripts/vault-token.sh $(ENV) create-admin

vault-configure:
	./ci/scripts/vault-configure.sh $(ENV)

deploy-platform:
	./ci/scripts/deploy-platform.sh $(ENV)

deploy-gitlab:
	./ci/scripts/deploy-gitlab.sh $(ENV)

prepare-gitlab-registry-projects:
	./ci/scripts/prepare-gitlab-registry-projects.sh $(ENV)

bootstrap-gitlab-app-ci:
	./ci/scripts/bootstrap-gitlab-app-ci.sh $(ENV)

deploy-app-charts:
	./ci/scripts/deploy-app-charts.sh $(ENV)

deploy-apps:
	./ci/scripts/deploy-apps.sh $(ENV)

docker-registry-login:
	./ci/scripts/docker-registry-login.sh $(ENV)

build-stub-images:
	./ci/scripts/build-stub-images.sh

test-stubs:
	./ci/scripts/test-stub-apps.sh

test-smoke:
	./ci/scripts/smoke-tests.sh $(ENV)

test-network:
	./ci/scripts/network-tests.sh $(ENV)

test-security:
	./ci/scripts/security-tests.sh $(ENV)

test-integration:
	./ci/scripts/integration-tests.sh $(ENV)

test-storage:
	./ci/scripts/storage-tests.sh $(ENV)

test-gitlab:
	./ci/scripts/gitlab-tests.sh $(ENV)

test-resilience:
	./ci/scripts/resilience-tests.sh $(ENV)

test-all: test-smoke test-network test-security test-integration test-storage test-resilience

test-load:
	./ci/scripts/load-test.sh $(ENV)

test-fail-node:
	./ci/scripts/fail-node-test.sh $(ENV)

package:
	git archive --format=tar.gz --prefix=deployment-kit/ -o deployment-kit-$(ENV).tar.gz HEAD:deployment-kit
