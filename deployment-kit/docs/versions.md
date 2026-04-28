# Версии компонентов

Версии зафиксированы явно, чтобы deployment-kit был воспроизводимым.

## Terraform providers
- `yandex-cloud/yandex`: `~> 0.201.0`
- `hashicorp/kubernetes`: `~> 2.38.0`
- `hashicorp/helm`: `~> 2.17.0`
- `hashicorp/vault`: `~> 5.9.0`

## Helm charts
- GitLab: `gitlab/gitlab` `9.11.1`
- GitLab Runner: bundled subchart declared by GitLab chart `9.11.1` (`gitlab/gitlab-runner` `0.87.0`, app `18.10.0`)
- Vault: `hashicorp/vault` `0.32.0`
- ingress-nginx: `ingress-nginx/ingress-nginx` `4.15.1`
- cert-manager: `v1.20.2`
- metrics-server: `metrics-server/metrics-server` `3.13.0`
- kube-prometheus-stack: `prometheus-community/kube-prometheus-stack` `84.3.0`
- prometheus-blackbox-exporter: `prometheus-community/prometheus-blackbox-exporter` `11.9.1`
- Loki: `grafana/loki` `7.0.0`
- Alloy: `grafana/alloy` `1.8.0` (`appVersion` `v1.16.0`)
- PostgreSQL: `bitnami/postgresql` `18.6.2`
- Redis: `bitnami/redis` `25.4.1`

## Yandex Cloud services
- Network Load Balancer для Kubernetes API и ingress.
- Cloud DNS, Certificate Manager и CDN используются в отдельном `terraform/edge`-слое и по умолчанию выключены для приватного домена `mdp`.

## GitLab bundled dependencies
- GitLab chart `9.11.1` declares bundled `gitlab-runner` chart `0.87.0` (`appVersion` `18.10.0`).
- Standalone `gitlab/gitlab-runner` `0.88.1` exists for GitLab Runner `18.11.1`, but it is not the dependency pinned by GitLab chart `9.11.1`.

При обновлении версии сначала запускается `make validate`, затем отдельный живой прогон на `vm-dev`.
