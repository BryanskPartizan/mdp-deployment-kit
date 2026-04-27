# Версии компонентов

Версии зафиксированы явно, чтобы deployment-kit был воспроизводимым.

## Terraform providers
- `yandex-cloud/yandex`: `~> 0.201.0`
- `hashicorp/kubernetes`: `~> 2.38.0`
- `hashicorp/helm`: `~> 2.17.0`
- `hashicorp/vault`: `~> 5.9.0`

## Helm charts
- GitLab: `gitlab/gitlab` `9.11.1`
- GitLab Runner: bundled subchart compatible with GitLab chart `9.11.1` (`gitlab/gitlab-runner` `0.88.1`)
- Vault: `hashicorp/vault` `0.32.0`
- ingress-nginx: `ingress-nginx/ingress-nginx` `4.15.1`
- cert-manager: `v1.20.2`
- metrics-server: `metrics-server/metrics-server` `3.13.0`
- kube-prometheus-stack: `prometheus-community/kube-prometheus-stack` `84.3.0`
- Loki: `grafana/loki` `7.0.0`
- Promtail: `grafana/promtail` `6.17.1`
- PostgreSQL: `bitnami/postgresql` `18.6.2`
- Redis: `bitnami/redis` `25.4.1`

При обновлении версии сначала запускается `make validate`, затем отдельный живой прогон на `vm-dev`.
