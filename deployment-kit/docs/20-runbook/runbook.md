# Runbook запуска и тестирования

Документ описывает полный порядок запуска deployment-kit в Yandex Cloud для self-hosted kubeadm-кластера и последующую проверку результата. Команды выполняются из каталога `deployment-kit`.

## 1. Что разворачивается

Поток запуска:

```text
Terraform -> Ansible kubeadm -> platform services -> Vault -> GitLab -> apps -> tests
```

В результате должны появиться:

- 3 control-plane VM и 2 worker VM;
- Yandex Network Load Balancer для Kubernetes API `6443`;
- Yandex Network Load Balancer для ingress `80/443 -> 30080/30443`;
- kubeadm HA-кластер с `controlPlaneEndpoint` на API-балансировщике;
- Vault HA с Raft-хранилищем;
- ingress-nginx, cert-manager, local-path-provisioner, metrics-server, Prometheus, Grafana, Loki, Alloy;
- GitLab и GitLab Runner controller в namespace `devops`, CI job pods в namespace `ci`;
- прикладной контур `api`, `gateway`, `frontend`, PostgreSQL, Redis в namespace `app`.

## 2. Локальные зависимости

На машине запуска нужны:

- `terraform`;
- `ansible-playbook`;
- `kubectl`;
- `helm`;
- `jq`;
- `curl`;
- `nc`;
- `ssh` с приватным ключом, соответствующим `ssh_public_key_path`;
- `k6`, если запускаются нагрузочные тесты.

Быстрая проверка:

```bash
terraform version
ansible-playbook --version
kubectl version --client
helm version
jq --version
curl --version
nc -h
```

Если `ansible-playbook` отсутствует, `make validate` пропустит Ansible syntax-check, но реальный `make kubeadm-bootstrap` без Ansible не выполнится.

## 3. Подготовка окружения

Перед выполнением команд deployment-kit подготовьте Yandex Cloud: billing, folder, service account, IAM roles, token, квоты, SSH-ключ и DNS-модель. Подробная инструкция находится в `docs/10-preparation/yandex-cloud-preparation.md`.

Перейдите в каталог deployment-kit:

```bash
cd deployment-kit
```

Скопируйте пример переменных:

```bash
cp .env.example .env
chmod 600 .env
```

Заполните `.env` реальными значениями. Минимальный набор для нормального запуска:

```bash
TF_VAR_yc_token=...
GRAFANA_ADMIN_PASSWORD=...
GITLAB_ROOT_PASSWORD=...
POSTGRES_APP_PASSWORD=...
POSTGRES_ADMIN_PASSWORD=...
APP_DOMAIN=pkhco.ru
TLS_CLUSTER_ISSUER=letsencrypt-prod
LETSENCRYPT_EMAIL=<email-for-acme>
REGISTRY_SERVER=registry.pkhco.ru
IMAGE_REGISTRY=registry.pkhco.ru
REGISTRY_USER=...
REGISTRY_PASSWORD=...
TF_VAR_app_secret_overrides='<json>'
```

Для Cloudflare DNS текущего публичного профиля дополнительно нужны:

```bash
TF_VAR_cloudflare_zone_id=<cloudflare-zone-id>
TF_VAR_cloudflare_api_token=<cloudflare-dns-token>
```

Публичный профиль не поддерживает приватные домены и non-prod issuers: deploy-скрипты принимают только публичный `APP_DOMAIN` и `TLS_CLUSTER_ISSUER=letsencrypt-prod`.

Загрузите переменные в текущую shell-сессию так, чтобы они были экспортированы дочерним процессам:

```bash
set -a
source .env
set +a
```

Для одноразового demo-стенда можно включить небезопасные demo-секреты:

```bash
export ALLOW_INSECURE_DEMO_SECRETS=true
```

Для stage/prod-like проверки этот режим не использовать.

## 4. Настройка Terraform environment

Этот шаг выполняется после подготовки Yandex Cloud из `docs/10-preparation/yandex-cloud-preparation.md`.

Основное окружение: `vm-dev`.

Проверьте файл:

```bash
vi environments/vm-dev/terraform.tfvars
```

Обязательные поля:

```hcl
yc_cloud_id         = "..."
yc_folder_id        = "..."
yc_zone             = "ru-central1-a"
ssh_public_key_path = "/absolute/path/to/id_ed25519.pub"
node_count_cp       = 3
node_count_worker   = 2
```

Рекомендуется ограничить CIDR-доступы вместо `0.0.0.0/0`:

```hcl
allowed_ssh_cidrs     = ["<your-ip>/32"]
allowed_api_cidrs     = ["<your-ip>/32"]
allowed_ingress_cidrs = ["<your-ip>/32"]
allowed_egress_cidrs  = ["0.0.0.0/0"] # сузьте до NAT/proxy CIDR, если в организации есть controlled egress
```

В шаблонных `terraform.tfvars` используется `203.0.113.10/32` как безопасный TEST-NET placeholder. Его нужно заменить перед реальным запуском, иначе SSH/API/ingress будут недоступны с вашей машины.

Для real deploy не делайте control-plane прерываемым. Если нужен экономичный режим, используйте только `worker_preemptible=true`, а `control_plane_preemptible` оставьте `false`. При наличии bastion/NAT gateway можно убрать публичный NAT с control-plane через `enable_control_plane_nat=false`.

Проверьте Ansible-параметры:

```bash
vi environments/vm-dev/ansible-vars.yml
vi environments/vm-dev/kubeadm-config.yml
```

В `ansible-vars.yml` дефолтный CNI должен быть Calico:

```yaml
cni_provider: calico
calico_version: "v3.31.4"
pod_subnet: "10.244.0.0/16"
```

Это важно для security baseline: обычный Flannel не применяет Kubernetes `NetworkPolicy`, поэтому `make test-security` будет падать на deny-сценариях.

## 5. Статическая проверка до запуска

```bash
make validate ENV=vm-dev
```

Что проверяется:

- `terraform fmt -check -recursive`;
- синтаксис shell-скриптов;
- рендеринг Helm charts приложений;
- рендеринг GitLab chart, если chart доступен локально;
- Ansible syntax-check, если установлен `ansible-playbook`;
- `terraform validate` для `terraform/vm`, `terraform/edge`, `terraform/platform`, `terraform/vault`.

Если Terraform provider или Helm chart ещё не скачаны, команде нужен доступ во внешние registry/repository.

## 6. Создание инфраструктуры

План:

```bash
make infra-plan ENV=vm-dev
```

Проверьте план. После этого примените:

```bash
make infra-apply ENV=vm-dev
```

После успешного `apply` должны появиться:

- `.artifacts/vm-dev/tfplan`;
- `.artifacts/vm-dev/terraform-outputs.json`;
- `ansible/inventory/generated/hosts.yml`;
- `.artifacts/vm-dev/ansible-vars.yml`;
- `.artifacts/vm-dev/kubeadm-config.yml`.

Проверка outputs:

```bash
jq '.api_external_ip.value, .ingress_external_ip.value, .control_planes.value, .workers.value' .artifacts/vm-dev/terraform-outputs.json
```

## 6.1. Настройка домена

Текущий `environments/vm-dev/edge.tfvars` настроен на публичный домен `pkhco.ru` в Cloudflare. Это единственный поддерживаемый профиль для TLS: все сертификаты выпускаются через production Let's Encrypt.

```bash
make edge-apply ENV=vm-dev
cat .artifacts/vm-dev/hosts-file
```

Для CLI-диагностики можно не менять системный DNS и использовать `curl --resolve`, но штатный сценарий использует реальные Cloudflare DNS-записи.

Для публичного `pkhco.ru` используется Cloudflare DNS only. Перед `make edge-apply` задайте Cloudflare credentials:

```bash
export TF_VAR_cloudflare_zone_id=<cloudflare-zone-id>
export TF_VAR_cloudflare_api_token=<cloudflare-dns-token>
make edge-apply ENV=vm-dev
```

Terraform создаст A-записи на ingress IP для `app.pkhco.ru`, `gateway.pkhco.ru`, `api.pkhco.ru`, `gitlab.pkhco.ru`, `registry.pkhco.ru`, `kas.pkhco.ru`, `grafana.pkhco.ru`, `k8s-admin.pkhco.ru`, `vault.pkhco.ru` и `minio.pkhco.ru`. В Cloudflare эти записи должны оставаться DNS only, без proxy.

Если раньше этот же `terraform/edge` state уже создавал Yandex Cloud DNS zone, перед переключением на Cloudflare посмотрите план:

```bash
make edge-plan ENV=vm-dev
```

Если в плане есть удаление старой `yandex_dns_zone` с `deletion_protection=true`, сначала примите решение: удалить старую Yandex zone через Terraform после снятия protection или оставить её как orphan state. Для текущего публичного домена `pkhco.ru` рабочим источником DNS должна быть Cloudflare zone.

Проверка SSH-доступа к первому узлу:

```bash
ansible -i ansible/inventory/generated/hosts.yml all -m ping
```

## 7. Сборка kubeadm-кластера

```bash
make kubeadm-bootstrap ENV=vm-dev
```

Ansible выполнит preflight-проверки, установит containerd/Kubernetes-пакеты, выполнит `kubeadm init`, подключит остальные control-plane и worker-узлы, поставит CNI и сохранит kubeconfig.

После завершения должен появиться:

```bash
.artifacts/vm-dev/admin.conf
```

Экспортируйте kubeconfig:

```bash
export KUBECONFIG=.artifacts/vm-dev/admin.conf
```

Проверки:

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl get --raw='/readyz?verbose'
```

Ожидаемый результат:

- все control-plane и worker-узлы в статусе `Ready`;
- CoreDNS, kube-proxy и CNI Pod'ы готовы;
- Kubernetes API доступен через внешний API NLB.

## 8. Развертывание платформенных сервисов

```bash
make deploy-platform ENV=vm-dev
```

Платформенный слой устанавливает cert-manager и создаёт только production ClusterIssuer `letsencrypt-prod`. Перед запуском публичные DNS-записи должны указывать на ingress IP, затем задайте:

```bash
export APP_DOMAIN=pkhco.ru
export TLS_CLUSTER_ISSUER=letsencrypt-prod
export LETSENCRYPT_EMAIL=admin@example.com
export K8S_ADMIN_ENABLED=true
export K8S_ADMIN_BASIC_AUTH_HTPASSWD='admin:<bcrypt-hash-from-htpasswd>'
```

`K8S_ADMIN_BASIC_AUTH_HTPASSWD` создаётся командой:

```bash
htpasswd -nbB admin '<strong-password>'
```

Staging Let's Encrypt в deployment-kit не используется: публичный профиль сразу выпускает production-сертификаты.

Скрипт устанавливает:

- namespaces;
- local-path-provisioner и default `StorageClass`;
- ingress-nginx;
- cert-manager и ClusterIssuer;
- metrics-server;
- kube-prometheus-stack;
- Grafana ingress `grafana.<APP_DOMAIN>`;
- Headlamp ingress `k8s-admin.<APP_DOMAIN>`, если `K8S_ADMIN_ENABLED=true`; доступ закрыт basic auth на ingress-nginx;
- prometheus-blackbox-exporter;
- Grafana dashboards, Prometheus alert rules и platform probes из `kubernetes/observability`;
- Loki;
- Alloy.

Проверки:

```bash
kubectl get ns
kubectl get sc
kubectl get clusterissuer
kubectl -n ingress-nginx get pods,svc
kubectl -n cert-manager get pods
kubectl -n observability get pods
kubectl -n observability rollout status daemonset/alloy --timeout=300s
kubectl -n observability get servicemonitor -l deployment-kit/component=alloy
kubectl -n observability get servicemonitor -l deployment-kit/component=endpoint-probe
kubectl -n observability get prometheusrule deployment-kit-platform-alerts
kubectl -n observability get configmap deployment-kit-grafana-dashboards
kubectl top nodes
```

Если `kubectl top nodes` не работает сразу, подождите 1-2 минуты: metrics-server может ещё собирать первые метрики.

Открыть Grafana локально:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

В Grafana должна появиться папка `Deployment Kit` с dashboards по кластеру, приложениям, endpoint'ам, Redis/PostgreSQL и платформенным компонентам.

GitLab probes добавляются командой `make deploy-gitlab`, а app/datastore probes — командой `make deploy-apps`, чтобы до установки этих компонентов мониторинг не создавал ложные endpoint alerts.

Доступ в Headlamp (`https://k8s-admin.<APP_DOMAIN>`) состоит из двух уровней:

1. basic auth на ingress-nginx, логин/пароль берутся из `K8S_ADMIN_BASIC_AUTH_HTPASSWD`;
2. Kubernetes token на странице входа Headlamp.

Получить token для текущей установки:

```bash
kubectl --kubeconfig .artifacts/vm-dev/admin.conf -n k8s-admin create token headlamp
```

Если нужно проверить ServiceAccount:

```bash
kubectl --kubeconfig .artifacts/vm-dev/admin.conf -n k8s-admin get sa
kubectl --kubeconfig .artifacts/vm-dev/admin.conf get clusterrolebinding | grep headlamp
```


## 9. Развертывание Vault

```bash
make deploy-vault ENV=vm-dev
```

Скрипт устанавливает `local-path` storage class, затем Terraform-слоем `terraform/platform` устанавливает Vault Helm release, service account для Kubernetes auth и ingress `vault.<APP_DOMAIN>`.

В `vm-dev` Vault запускается в 3 replica. Если в стенде только 2 worker-узла, третья replica допускается на control-plane через toleration `node-role.kubernetes.io/control-plane:NoSchedule`. Для production-режима предпочтительнее добавить третий worker-узел и убрать необходимость размещать Vault на control-plane.

Проверка:

```bash
kubectl -n security get pods,svc,pvc
```

Первичная инициализация и unseal:

```bash
make vault-init ENV=vm-dev
```

Файл с bootstrap-материалами:

```bash
.artifacts/vm-dev/vault-init.json
```

Он содержит unseal keys и root token, поэтому должен оставаться локальным секретным артефактом и не должен попадать в Git.

Настройка Vault auth, policies и KV v2:

```bash
make vault-configure ENV=vm-dev
```

Проверки:

```bash
kubectl -n security get pods
kubectl -n security exec vault-0 -- vault status
kubectl -n security get secret vault-auth-token
kubectl -n security get ingress
```

Получить token для входа в Vault UI:

```bash
make vault-admin-token ENV=vm-dev
```

Команда создаёт короткоживущий token с policy `root`, TTL по умолчанию `24h`, сохраняет JSON в `.artifacts/vm-dev/vault-admin-token.json` и печатает сам token отдельной строкой. Изменить TTL:

```bash
VAULT_ADMIN_TOKEN_TTL=2h make vault-admin-token ENV=vm-dev
```

Если нужно вывести bootstrap root token из локального init-файла:

```bash
make vault-token ENV=vm-dev
```

Root token использовать только для bootstrap/debug. Для регулярного входа в UI предпочтительнее создавать короткоживущий admin token.

Ожидаемый результат:

- `vault-0`, `vault-1`, `vault-2` не sealed;
- Vault injector запущен;
- ingress `vault.pkhco.ru` получил TLS secret от production Let's Encrypt;
- Terraform `terraform/vault` применился без ошибок.

## 10. Развертывание GitLab

```bash
export APP_DOMAIN=pkhco.ru
export TLS_CLUSTER_ISSUER=letsencrypt-prod
make deploy-gitlab ENV=vm-dev
```

GitLab разворачивается в namespace `devops`, использует ingress `gitlab.<APP_DOMAIN>` и registry `registry.<APP_DOMAIN>`. Для публичного стенда `pkhco.ru` это `gitlab.pkhco.ru` и `registry.pkhco.ru`. Root password берётся из `GITLAB_ROOT_PASSWORD` или из уже существующего Kubernetes Secret.
После успешного Helm rollout скрипт добавляет blackbox probes для `gitlab.<APP_DOMAIN>` и `registry.<APP_DOMAIN>`.

GitLab Runner запускается в кластере и регистрируется через внутренний Service `gitlab-webservice-default.devops.svc.cluster.local:8080`. Это снижает зависимость runner от внешнего DNS, при этом внешние GitLab и registry ingress должны получать production TLS от Let's Encrypt.

Скрипт не пересоздаёт `gitlab-root-password`, если secret уже существует. Для осознанной ротации используйте `ROTATE_GITLAB_ROOT_PASSWORD=true` и заранее проверьте процедуру смены root password в GitLab.

Если используется публичный домен, задайте `APP_DOMAIN=<domain>` перед запуском. Скрипт передаст `global.hosts.domain`, `gitlab.<domain>` и `registry.<domain>` в GitLab chart.

Проверки:

```bash
kubectl -n devops get pods,svc,ingress,pvc
kubectl -n devops get secret gitlab-root-password
make test-gitlab ENV=vm-dev
```

Получить root password:

```bash
kubectl -n devops get secret gitlab-root-password -o jsonpath='{.data.password}' | base64 --decode
echo
```

Проверить GitLab через ingress NLB без изменения `/etc/hosts`:

```bash
INGRESS_IP=$(jq -r '.ingress_external_ip.value' .artifacts/vm-dev/terraform-outputs.json)
curl -kI --resolve "gitlab.pkhco.ru:443:${INGRESS_IP}" https://gitlab.pkhco.ru/users/sign_in
curl -kI --resolve "registry.pkhco.ru:443:${INGRESS_IP}" https://registry.pkhco.ru/v2/
```

Для публичного режима эти записи создаёт `make edge-apply` в Cloudflare. `mdp` больше не используется в поддерживаемом deploy-профиле.

## 11. Подготовка образов приложений

Прикладные Helm charts ожидают образы:

```text
registry.pkhco.ru/platform/api:0.2.0
registry.pkhco.ru/platform/gateway:0.2.0
registry.pkhco.ru/platform/frontend:0.2.0
```

Deployment-kit поставляет минимальные demo-заглушки в каталоге `apps/`:

- `api` создаёт, читает и обновляет карточки лидов по маршрутам `/leads` и `/leads/:id`;
- `gateway` проксирует маршруты `/leads`, `/entities` и `/test-runs` в API;
- `frontend` отдаёт CRM-доску лидов, таблицу, форму редактирования и вкладку `Админка` с результатами тестов.

Проверить заглушки локально без Kubernetes:

```bash
make test-stubs
```

Собрать образы:

```bash
make build-stub-images
```

Опубликовать образы в GitLab Container Registry:

```bash
make prepare-gitlab-registry-projects ENV=vm-dev
make docker-registry-login ENV=vm-dev
PUSH_IMAGES=true make build-stub-images
```

При публикации локально с macOS скрипт использует `docker buildx build --platform linux/amd64 --push`. Это важно: VM в Yandex Cloud используют `linux/amd64`, а образ, случайно собранный как ARM64, приводит к `ImagePullBackOff` с ошибкой `no match for platform in manifest`.

`make prepare-gitlab-registry-projects` создаёт проекты `platform/api`, `platform/gateway` и `platform/frontend`. Без этих проектов push в `registry.pkhco.ru/platform/<app>` завершается `insufficient_scope` или `repository does not exist`.

Если используется другой registry или tag:

```bash
IMAGE_REGISTRY=registry.pkhco.ru APP_IMAGE_TAG=0.2.0 PUSH_IMAGES=true make build-stub-images
APP_IMAGE_TAG=0.2.0 make deploy-apps ENV=vm-dev
```

Если образы отсутствуют в registry, `make deploy-apps` дойдёт до rollout и завершится ошибкой `ImagePullBackOff`.

Пример проверки registry login после запуска GitLab:

```bash
make docker-registry-login ENV=vm-dev
```

Команда `make docker-registry-login` берёт пароль из `devops/gitlab-root-password` и выполняет login в `registry.<APP_DOMAIN>`. Для публичного `pkhco.ru` с production Let's Encrypt `REGISTRY_TRUST_MODE=none`, дополнительных CA/insecure настроек Docker не требуется.

Self-signed/insecure Docker trust не используется в публичном профиле. Если `docker login` требует CA или insecure registry для `registry.pkhco.ru`, значит TLS ещё не выпущен Let's Encrypt или ingress смотрит не на тот host.

Если пароль root не должен использоваться для registry, задайте `REGISTRY_USER` и `REGISTRY_PASSWORD`. Для публичного профиля используйте `TLS_CLUSTER_ISSUER=letsencrypt-prod` и `REGISTRY_TRUST_MODE=none`.

## 12. Развертывание приложений

```bash
make deploy-apps ENV=vm-dev
```

Скрипт создаёт или обновляет registry secret, создаёт PostgreSQL secret только если его ещё нет, устанавливает PostgreSQL, Redis, API, gateway, frontend, RBAC, NetworkPolicy и backup-манифесты. Если `REGISTRY_PASSWORD` не задан, `gitlab-registry` secret автоматически собирается из `devops/gitlab-root-password` с пользователем `root`.
После успешного rollout скрипт добавляет blackbox probes для внутренних health endpoint'ов, ingress endpoint'ов, PostgreSQL и Redis.

PostgreSQL secret не пересоздаётся при повторном запуске, чтобы не разойтись с паролем уже инициализированной БД. Для явной ротации задайте `ROTATE_POSTGRES_SECRET=true`, но перед этим подготовьте процедуру смены пароля в PostgreSQL и Vault secret overrides.

Проверки:

```bash
kubectl -n app get pods,svc,ingress,pvc
kubectl -n app rollout status statefulset/postgres-postgresql --timeout=600s
kubectl -n app rollout status statefulset/redis-master --timeout=600s
kubectl -n app rollout status deployment/api --timeout=300s
kubectl -n app rollout status deployment/gateway --timeout=300s
kubectl -n app rollout status deployment/frontend --timeout=300s
```

Проверка внешнего frontend:

```bash
INGRESS_IP=$(jq -r '.ingress_external_ip.value' .artifacts/vm-dev/terraform-outputs.json)
curl -kfsS --resolve "app.pkhco.ru:443:${INGRESS_IP}" https://app.pkhco.ru/health
```

Проверка gateway:

```bash
curl -kfsS --resolve "gateway.pkhco.ru:443:${INGRESS_IP}" https://gateway.pkhco.ru/health
```

## 13. Полный набор тестов

Базовая последовательность после `deploy-apps`:

```bash
make test-smoke ENV=vm-dev
make test-network ENV=vm-dev
make test-security ENV=vm-dev
make test-integration ENV=vm-dev
make test-storage ENV=vm-dev
make test-gitlab ENV=vm-dev
make test-resilience ENV=vm-dev
```

В консоли выводятся только статусы верхнеуровневых проверок. Полные логи, JSON и HTML-отчёт сохраняются в:

```text
.artifacts/vm-dev/test-results/
```

Последние отчёты:

```text
.artifacts/vm-dev/test-results/latest.json
.artifacts/vm-dev/test-results/latest.html
```

Если ingress gateway доступен, результат теста дополнительно публикуется в приложение и отображается во frontend на вкладке `Админка`.

Короткий регулярный набор:

```bash
make test-all ENV=vm-dev
```

`test-all` включает smoke, network, security, integration, storage и resilience. GitLab-тест и нагрузочный тест запускаются отдельно.

## 14. Что проверяют тесты

### Smoke

```bash
make test-smoke ENV=vm-dev
```

Проверяет:

- rollout `api`, `gateway`, `frontend`;
- наличие ingress;
- `ClusterIssuer`;
- service accounts приложений;
- внешнюю доступность frontend, если есть Terraform outputs.

### Network

```bash
make test-network ENV=vm-dev
```

Проверяет:

- разрешённую связанность frontend -> gateway;
- разрешённую связанность gateway -> API;
- разрешённую связанность API -> PostgreSQL/Redis;
- внешние entrypoints API NLB и ingress NLB.

### Security

```bash
make test-security ENV=vm-dev
```

Проверяет:

- действие `NetworkPolicy`;
- ожидаемые ограничения RBAC для прикладных service accounts.

Если тест сразу сообщает `Обнаружен kube-flannel без NetworkPolicy controller`, текущий live-кластер собран на Flannel. Для прохождения security baseline нужен CNI с policy enforcement, например дефолтный Calico из текущей версии deployment-kit. Для уже поднятого Flannel-кластера безопасный путь — `kubeadm-reset` и повторный bootstrap; live-миграцию CNI выполнять только отдельным контролируемым окном.

### Integration

```bash
make test-integration ENV=vm-dev
```

Проверяет:

- готовность платформенных компонентов;
- полный прикладной flow;
- create/read/update карточек лидов;
- работу Vault Agent Injector и доставку секрета в Pod.

### Storage

```bash
make test-storage ENV=vm-dev
```

Создаёт временный PVC, пишет данные из одного Pod и читает их из другого Pod.

### GitLab

```bash
make test-gitlab ENV=vm-dev
```

Проверяет namespace `devops`, root secret, ingress, PVC, rollout Deployment/StatefulSet и HTTP-ответы GitLab/Registry через ingress NLB.

### Resilience

```bash
make test-resilience ENV=vm-dev
```

Проверяет состояние control plane, Kubernetes API и базовую готовность HA-контура без разрушительных действий.

Управляемый drain worker-узла:

```bash
make test-fail-node ENV=vm-dev
```

Эту проверку запускать вручную: она меняет состояние worker-узла через drain/uncordon.

### Load

```bash
make test-load ENV=vm-dev
```

Использует `k6` и сценарии из `tests/load`. Перед запуском убедитесь, что ingress доступен и приложение отвечает на health endpoints.

## 15. Запуск через GitLab CI

Корневой `.gitlab-ci.yml` по умолчанию запускает app pipeline для demo-заглушек: build -> scan -> deploy -> smoke. Инфраструктурный pipeline подключается только при `RUN_INFRA_PIPELINE=true`, чтобы обычный push приложения не пытался управлять Yandex Cloud.

Автоматически создать registry-проекты `platform/api`, `platform/gateway`, `platform/frontend`, GitLab project `platform/deployment-kit`, записать CI variables и запушить текущую ветку:

```bash
make bootstrap-gitlab-app-ci ENV=vm-dev
```

Скрипт записывает в проект:

```text
APP_DOMAIN
APP_NAMESPACE
TLS_CLUSTER_ISSUER
IMAGE_REGISTRY
REGISTRY_SERVER
REGISTRY_USER
REGISTRY_PASSWORD
KUBECONFIG_B64
RUN_INFRA_PIPELINE=false
```

Важно: `git push` отправляет только уже созданные commits. Если в рабочем дереве есть незакоммиченные изменения, скрипт предупредит об этом.

По умолчанию `make bootstrap-gitlab-app-ci` кодирует текущий `.artifacts/<env>/admin.conf` в `KUBECONFIG_B64`. Для более строгой модели заранее передайте `KUBECONFIG_B64` от отдельного deployer kubeconfig с namespace-scoped правами.

Инфраструктурный pipeline описан в `ci/templates/infra-pipeline.yml`.

Обязательные CI variables:

```text
ENV=vm-dev
RUN_INFRA_PIPELINE=true
TF_VAR_yc_token
GRAFANA_ADMIN_PASSWORD
GITLAB_ROOT_PASSWORD
POSTGRES_APP_PASSWORD
POSTGRES_ADMIN_PASSWORD
TF_VAR_app_secret_overrides
```

`kubeadm_bootstrap` публикует только `.artifacts/<env>/admin.conf` как restricted artifact с доступом maintainer и коротким TTL. Join-команды не публикуются в CI artifacts.

Для приватных образов:

```text
REGISTRY_SERVER
REGISTRY_USER
REGISTRY_PASSWORD
```

Для GitLab CI можно использовать стандартные переменные:

```text
CI_REGISTRY
CI_REGISTRY_USER
CI_REGISTRY_PASSWORD
```

Для app pipeline из `ci/templates/app-pipeline.yml` передайте `KUBECONFIG_B64` как protected/masked variable. Это base64 от kubeconfig с минимально нужными правами deployer'а, а не полный локальный `admin.conf`.

Рекомендуемый порядок ручных стадий:

```text
validate -> plan -> apply -> kubeadm_bootstrap -> deploy_vault -> deploy_platform -> deploy_gitlab -> deploy_apps -> smoke -> network -> security -> integration -> gitlab -> resilience
```

Cleanup-стадии `kubeadm_reset` и `infra_destroy` требуют явного подтверждения через переменные `CONFIRM_RESET` и `CONFIRM_DESTROY`.

## 16. Пересборка Kubernetes без удаления VM

Если нужно пересобрать kubeadm-кластер на уже созданных VM:

```bash
CONFIRM_RESET=vm-dev make kubeadm-reset ENV=vm-dev
make kubeadm-bootstrap ENV=vm-dev
```

Reset очищает kubeadm, etcd, kubelet, CNI и локальные bootstrap-артефакты на узлах, но не удаляет VM, сети и балансировщики.

Полная очистка iptables по умолчанию выключена, чтобы не удалить host-level firewall вне Kubernetes. Если нужно вернуть старое поведение для полностью одноразовых VM, задайте `kubeadm_reset_flush_iptables: true` в Ansible vars.

После reset заново выполняются:

```bash
make deploy-platform ENV=vm-dev
make deploy-vault ENV=vm-dev
make vault-init ENV=vm-dev
make vault-configure ENV=vm-dev
make deploy-gitlab ENV=vm-dev
make deploy-apps ENV=vm-dev
```

## 17. Удаление инфраструктуры

Сначала удалите edge-слой, пока доступны старые Terraform outputs с IP ingress NLB:

```bash
CONFIRM_EDGE_DESTROY=vm-dev make edge-destroy ENV=vm-dev
```

Полное удаление Yandex Cloud ресурсов:

```bash
CONFIRM_DESTROY=vm-dev make infra-destroy ENV=vm-dev
```

Команда удаляет ресурсы Terraform-слоя `terraform/vm`. Локальные `.artifacts` остаются на машине запуска и могут быть удалены вручную после проверки, что они больше не нужны.

## 18. Частые проверки при ошибках

Проверить состояние узлов:

```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

Проверить системные Pod'ы:

```bash
kubectl -n kube-system get pods -o wide
kubectl -n kube-system describe pod <pod-name>
```

Проверить pending PVC:

```bash
kubectl get pvc -A
kubectl describe pvc -n <namespace> <pvc-name>
kubectl get sc
```

Проверить ingress:

```bash
kubectl -n ingress-nginx get pods,svc
kubectl get ingress -A
```

Проверить внешний IP ingress:

```bash
jq -r '.ingress_external_ip.value' .artifacts/vm-dev/terraform-outputs.json
```

Проверить image pull:

```bash
kubectl -n app describe pod <pod-name>
kubectl -n app get secret gitlab-registry -o yaml
```

Если Pod получает `401 Unauthorized` при обращении к `https://gitlab.pkhco.ru/jwt/auth`, обновите registry secret и перезапустите rollout:

```bash
make prepare-gitlab-registry-projects ENV=vm-dev
make deploy-apps ENV=vm-dev
kubectl -n app rollout restart deployment/api deployment/gateway deployment/frontend
```

Если Pod получает `no match for platform in manifest`, перезапушьте образы под `linux/amd64`:

```bash
make docker-registry-login ENV=vm-dev
IMAGE_PLATFORM=linux/amd64 PUSH_IMAGES=true make build-stub-images
kubectl --kubeconfig .artifacts/vm-dev/admin.conf -n app rollout restart deployment/api deployment/gateway deployment/frontend
```

Проверить Vault injection:

```bash
kubectl -n app describe pod <pod-name>
kubectl -n security get pods
kubectl -n security logs deploy/vault-agent-injector
```

Проверить GitLab:

```bash
kubectl -n devops get pods,svc,ingress,pvc
kubectl -n devops describe pod <pod-name>
kubectl -n devops logs <pod-name>
```

## 19. Критерий успешного запуска

Стенд считается рабочим, если выполнены условия:

- `make validate` завершился успешно;
- `make infra-apply` создал VM, inventory и Terraform outputs;
- `make kubeadm-bootstrap` создал HA kubeadm-кластер, все узлы `Ready`;
- Vault initialized/unsealed и `make vault-configure` завершился успешно;
- platform services готовы;
- GitLab доступен через `gitlab.pkhco.ru`, registry отвечает на `/v2/`;
- приложения успешно развернуты и отвечают через ingress;
- `make test-smoke`, `make test-network`, `make test-security`, `make test-integration`, `make test-storage`, `make test-gitlab`, `make test-resilience` завершились без ошибок.
