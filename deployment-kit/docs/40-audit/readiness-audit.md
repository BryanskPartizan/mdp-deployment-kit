# Аудит готовности к реальному деплою

Дата прохода: 28 апреля 2026.

## Проверки, выполненные локально

Выполнено:

```bash
make validate
helm template gitlab gitlab/gitlab --version 9.11.1 --namespace devops -f kubernetes/platform/gitlab/values.yaml -f kubernetes/platform/gitlab/values-dev.yaml
helm template gitlab gitlab/gitlab --version 9.11.1 --namespace devops -f kubernetes/platform/gitlab/values.yaml -f kubernetes/platform/gitlab/values-stage.yaml
helm template alloy grafana/alloy --version 1.8.0 --namespace observability -f kubernetes/base/alloy-values.yaml
helm lint kubernetes/apps/api -f kubernetes/apps/api/values.yaml -f kubernetes/apps/api/values-dev.yaml
helm lint kubernetes/apps/gateway -f kubernetes/apps/gateway/values.yaml -f kubernetes/apps/gateway/values-dev.yaml
helm lint kubernetes/apps/frontend -f kubernetes/apps/frontend/values.yaml -f kubernetes/apps/frontend/values-dev.yaml
terraform -chdir=terraform/edge validate
```

Результат: локальная статическая проверка проходит. `make validate` проверяет shell syntax, Grafana dashboard JSON, Helm template для platform/app/GitLab charts, Ansible syntax-check и Terraform validate.

## Совместимость версий

Зафиксированы версии Terraform providers и Helm charts в `docs/00-overview/versions.md`.

Ключевые проверки:
- GitLab chart `9.11.1` рендерится с dev/stage values;
- GitLab chart `9.11.1` имеет appVersion `18.11.1`;
- bundled GitLab Runner внутри GitLab chart `9.11.1` — chart `0.87.0`, appVersion `18.10.0`;
- standalone GitLab Runner `0.88.1` существует, но не является dependency GitLab chart `9.11.1`;
- Alloy chart `1.8.0` рендерится и заменяет Promtail;
- Loki chart `7.0.0` рендерится с TSDB schema config;
- kube-prometheus-stack, ingress-nginx, cert-manager, metrics-server, PostgreSQL и Redis рендерятся через `make validate`.

## Edge, DNS и CDN

Сделано:
- дефолтный домен заменён на публичный `pkhco.ru`;
- добавлен `terraform/edge` для Cloudflare DNS only режима, Cloud DNS, Certificate Manager и CDN;
- добавлены `make edge-plan` и `make edge-apply`;
- hosts-файл сохраняется как `.artifacts/<env>/hosts-file` только как диагностический fallback;
- Let's Encrypt issuer включается только как production `TLS_CLUSTER_ISSUER=letsencrypt-prod`;
- CDN выключен по умолчанию и предназначен для frontend/static, а не для GitLab/API/registry.

Остаточные ограничения:
- публичный DNS/CDN нельзя полностью подтвердить без реального домена и delegation NS-записей;
- для CDN нужно проверить cache-control реального frontend после появления production images;
- для публичного Let's Encrypt режима нужен live-прогон HTTP-01 challenge.

## GitLab hardening

Сделано:
- root password передаётся через Kubernetes Secret `gitlab-root-password`;
- secret `gitlab-root-password` не пересоздаётся при повторном deploy без явного `ROTATE_GITLAB_ROOT_PASSWORD=true`;
- public signup отключён через `global.appConfig.initialDefaults.signupEnabled: false`;
- product usage data отключён на initial install;
- bundled nginx-ingress/cert-manager/prometheus выключены, используются platform-компоненты deployment-kit;
- Runner manager работает в `devops`, job pods запускаются в `ci`;
- Runner RBAC ограничен Role в namespace `ci`, без cluster-wide access;
- Runner job pods запускаются без privileged mode и с resource requests/limits;
- Registry включён и публикуется через ingress `registry.pkhco.ru`.

Остаточные ограничения:
- bundled PostgreSQL/Redis/MinIO подходят для самодостаточного стенда, но не для production-grade GitLab;
- TLS GitLab выпускается через production Let's Encrypt ClusterIssuer `letsencrypt-prod`;
- GitLab backup/restore нужно выделить в отдельную процедуру перед production-like использованием.

## Observability

Сделано:
- Promtail удалён;
- Alloy установлен DaemonSet'ом через `grafana/alloy`;
- Alloy собирает Pod logs через Kubernetes API, без hostPath `/var/log`;
- Alloy отправляет Kubernetes events в Loki;
- Alloy RBAC задан вручную и минимизирован до `pods`, `pods/log`, `namespaces`, `events`;
- Grafana dashboards, blackbox probes и PrometheusRule проходят локальную проверку.

## Секреты

Сделано:
- `.env`, `.artifacts`, kubeconfig, Terraform state, generated inventory и service account keys игнорируются Git;
- demo-секреты в deploy scripts доступны только при `ALLOW_INSECURE_DEMO_SECRETS=true`;
- Vault app secrets по умолчанию требуют `TF_VAR_app_secret_overrides`;
- GitLab/Grafana/PostgreSQL пароли берутся из переменных окружения или CI variables.
- PostgreSQL secret создаётся только при отсутствии; повторный deploy не ротирует пароль без `ROTATE_POSTGRES_SECRET=true`;
- kubeadm join-команды не публикуются как CI artifacts, а `admin.conf` ограничен maintainer-доступом и коротким TTL.

Остаточные ограничения:
- bootstrap-материалы Vault сохраняются локально в `.artifacts/<env>/vault-init.json`; файл защищается правами `0600`, но требует операционной процедуры хранения/ротации;
- для production-grade модели стоит вынести все bootstrap secrets в отдельное защищённое хранилище.

## Сеть и доступы

Сделано:
- SSH/API/ingress CIDR в шаблонах заменены с `0.0.0.0/0` на TEST-NET placeholder `203.0.113.10/32`;
- Kubernetes API публикуется через отдельный NLB;
- ingress публикуется через отдельный NLB;
- app namespace использует default deny и явные allow rules;
- app chart egress больше не открыт полностью: разрешены только DNS, Vault и нужные service-to-service/datastore маршруты;
- app workloads получили PDB, topology spread и baseline Pod security context;
- app deployer вынесен в отдельный ServiceAccount `app-deployer`;
- observability namespace имеет только необходимые разрешения для probes.

Остаточные ограничения:
- egress security group по умолчанию открыт на `0.0.0.0/0`, потому что узлы должны скачивать пакеты и образы без отдельного NAT/proxy слоя, но теперь диапазон вынесен в `allowed_egress_cidrs`;
- namespace `devops` не закрыт default-deny NetworkPolicy из-за сложности внутренних потоков GitLab chart;
- для production нужно добавить egress proxy/NAT policy и отдельный набор NetworkPolicy для GitLab.

## Известные production gaps

Перед настоящей production эксплуатацией нужно:
- включить TLS на Vault listener и настроить сертификаты;
- убрать `--kubelet-insecure-tls` у metrics-server после настройки kubelet serving certificates;
- перевести GitLab PostgreSQL/Redis/Object Storage на managed/external сервисы;
- добавить GitLab backup/restore;
- расширить supply-chain проверки образов: подписи образов; SBOM и базовый Trivy scan добавлены в app pipeline template;
- подготовить реальные demo/app images и проверить registry push/pull;
- повторять полный live-прогон в Yandex Cloud перед значимыми изменениями инфраструктурных сценариев.

## Контрольный live-прогон

Для подтверждения готовности стенда выполняется полный live-прогон:

```bash
make infra-plan ENV=vm-dev
make infra-apply ENV=vm-dev
make edge-apply ENV=vm-dev
make kubeadm-bootstrap ENV=vm-dev
make deploy-platform ENV=vm-dev
make deploy-vault ENV=vm-dev
make vault-init ENV=vm-dev
make vault-configure ENV=vm-dev
make deploy-gitlab ENV=vm-dev
make deploy-apps ENV=vm-dev
make test-smoke ENV=vm-dev
make test-network ENV=vm-dev
make test-security ENV=vm-dev
make test-integration ENV=vm-dev
make test-storage ENV=vm-dev
make test-gitlab ENV=vm-dev
make test-resilience ENV=vm-dev
```

Критерий готовности: все команды выше завершаются успешно, GitLab Registry принимает push/pull, Alloy отправляет логи в Loki, Grafana dashboards показывают данные, blackbox probes зелёные.

Фактический контрольный прогон `vm-dev` оформлен в каталоге [`../../../execution-log`](../../../execution-log).
