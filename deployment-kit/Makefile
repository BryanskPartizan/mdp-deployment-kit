SHELL := /bin/bash
ENV ?= vm-dev
ARTIFACTS_DIR ?= .artifacts/$(ENV)
KUBECONFIG ?= $(ARTIFACTS_DIR)/admin.conf

export KUBECONFIG

.PHONY: help infra-plan infra-apply kubeadm-bootstrap deploy-platform deploy-apps test-smoke test-load test-fail-node render-inventory package

help:
	@echo "Targets: infra-plan infra-apply kubeadm-bootstrap deploy-platform deploy-apps test-smoke test-load test-fail-node package"

infra-plan:
	./ci/scripts/terraform-plan.sh $(ENV)

infra-apply:
	./ci/scripts/terraform-apply.sh $(ENV)

kubeadm-bootstrap:
	./ci/scripts/ansible-kubeadm-bootstrap.sh $(ENV)

deploy-platform:
	./ci/scripts/deploy-platform.sh $(ENV)

deploy-apps:
	./ci/scripts/deploy-apps.sh $(ENV)

test-smoke:
	./ci/scripts/smoke-tests.sh $(ENV)

test-load:
	./ci/scripts/load-test.sh $(ENV)

test-fail-node:
	./ci/scripts/fail-node-test.sh $(ENV)

package:
	tar -czf deployment-kit-$(ENV).tar.gz .
