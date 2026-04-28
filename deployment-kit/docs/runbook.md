# Runbook запуска и тестирования

Документ описывает полный порядок запуска deployment-kit в Yandex Cloud для self-hosted kubeadm-кластера и последующую проверку результата. Команды выполняются из каталога `deployment-kit`.

## 1. Что разворачивается

Поток запуска:

```text
Terraform -> Ansible kubeadm -> Vault -> platform services -> GitLab -> apps -> tests
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

Перед выполнением команд deployment-kit подготовьте Yandex Cloud: billing, folder, service account, IAM roles, token, квоты, SSH-ключ и DNS-модель. Подробная инструкция находится в `docs/yandex-cloud-preparation.md`.

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
APP_DOMAIN=mdp
TLS_CLUSTER_ISSUER=test-selfsigned
REGISTRY_SERVER=registry.mdp
IMAGE_REGISTRY=registry.mdp
REGISTRY_USER=...
REGISTRY_PASSWORD=...
TF_VAR_app_secret_overrides={...}
```

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

Этот шаг выполняется после подготовки Yandex Cloud из `docs/yandex-cloud-preparation.md`.

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

## 6.1. Настройка приватного домена mdp

Стартовый домен стенда — `mdp`. Он не требует публичной DNS-зоны и работает через локальные hosts-записи.

```bash
make edge-apply ENV=vm-dev
cat .artifacts/vm-dev/hosts-file
```

Для браузерного доступа добавьте содержимое `.artifacts/vm-dev/hosts-file` в локальный `/etc/hosts`. Дополнительно скрипт создаёт доменный alias, например `.artifacts/vm-dev/hosts-mdp`. Для CLI-проверок можно не менять системный DNS и использовать `curl --resolve`.

Для реального публичного домена или CDN используйте `docs/domain-cdn.md` и `environments/vm-dev/edge.tfvars`.

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

## 8. Развертывание Vault

```bash
make deploy-vault ENV=vm-dev
```

Скрипт устанавливает `local-path` storage class, затем Terraform-слоем `terraform/platform` устанавливает Vault Helm release и service account для Kubernetes auth.

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
```

Ожидаемый результат:

- `vault-0`, `vault-1`, `vault-2` не sealed;
- Vault injector запущен;
- Terraform `terraform/vault` применился без ошибок.

## 9. Развертывание платформенных сервисов

```bash
make deploy-platform ENV=vm-dev
```

По умолчанию cert-manager создаёт локальный CA issuer `test-selfsigned`. Это правильный режим для приватного `mdp`. Для публичного домена предварительно настройте DNS, затем задайте:

```bash
export APP_DOMAIN=example.com
export TLS_CLUSTER_ISSUER=letsencrypt-staging
export LETSENCRYPT_EMAIL=admin@example.com
```

После проверки staging-issuer можно перейти на `TLS_CLUSTER_ISSUER=letsencrypt-prod`.

Скрипт устанавливает:

- namespaces;
- local-path-provisioner и default `StorageClass`;
- ingress-nginx;
- cert-manager и ClusterIssuer;
- metrics-server;
- kube-prometheus-stack;
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

В Grafana должна появиться папка `Deployment Kit` с dashboards по кластеру, приложениям, endpoint'ам и платформенным компонентам.

GitLab probes добавляются командой `make deploy-gitlab`, а app/datastore probes — командой `make deploy-apps`, чтобы до установки этих компонентов мониторинг не создавал ложные endpoint alerts.

## 10. Развертывание GitLab

```bash
make deploy-gitlab ENV=vm-dev
```

GitLab разворачивается в namespace `devops`, использует ingress `gitlab.mdp` и registry `registry.mdp`. Root password берётся из `GITLAB_ROOT_PASSWORD` или из уже существующего Kubernetes Secret.
После успешного Helm rollout скрипт добавляет blackbox probes для `gitlab.mdp` и `registry.mdp`.

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
curl -kI --resolve "gitlab.mdp:443:${INGRESS_IP}" https://gitlab.mdp/users/sign_in
curl -kI --resolve "registry.mdp:443:${INGRESS_IP}" https://registry.mdp/v2/
```

Для доступа из браузера добавьте в локальный DNS или `/etc/hosts`:

```text
<INGRESS_IP> app.mdp gateway.mdp api.mdp gitlab.mdp registry.mdp minio.mdp
```

## 11. Подготовка образов приложений

Прикладные Helm charts ожидают образы:

```text
registry.mdp/platform/api:0.1.0
registry.mdp/platform/gateway:0.1.0
registry.mdp/platform/frontend:0.1.0
```

До финального прохода с собственными demo-образами есть два варианта:

1. Собрать и загрузить реальные образы в GitLab Container Registry.
2. Временно переопределить `image.repository` и `image.tag` в `kubernetes/apps/*/values-*.yaml` на уже существующие тестовые образы.

Если образы отсутствуют, `make deploy-apps` дойдёт до rollout и завершится ошибкой `ImagePullBackOff`.

Пример проверки registry login после запуска GitLab:

```bash
docker login registry.mdp
```

При self-signed TLS может потребоваться добавить CA в Docker/containerd trust store или временно настроить registry как insecure registry только для demo-стенда.

## 12. Развертывание приложений

```bash
make deploy-apps ENV=vm-dev
```

Скрипт создаёт или обновляет registry secret, создаёт PostgreSQL secret только если его ещё нет, устанавливает PostgreSQL, Redis, API, gateway, frontend, RBAC, NetworkPolicy и backup-манифесты.
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
curl -kfsS --resolve "app.mdp:443:${INGRESS_IP}" https://app.mdp/health
```

Проверка gateway:

```bash
curl -kfsS --resolve "gateway.mdp:443:${INGRESS_IP}" https://gateway.mdp/health
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

### Integration

```bash
make test-integration ENV=vm-dev
```

Проверяет:

- готовность платформенных компонентов;
- полный прикладной flow;
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

Pipeline описан в `ci/templates/infra-pipeline.yml`.

Обязательные CI variables:

```text
ENV=vm-dev
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
make deploy-vault ENV=vm-dev
make vault-init ENV=vm-dev
make vault-configure ENV=vm-dev
make deploy-platform ENV=vm-dev
make deploy-gitlab ENV=vm-dev
make deploy-apps ENV=vm-dev
```

## 17. Удаление инфраструктуры

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
- GitLab доступен через `gitlab.mdp`, registry отвечает на `/v2/`;
- приложения успешно развернуты и отвечают через ingress;
- `make test-smoke`, `make test-network`, `make test-security`, `make test-integration`, `make test-storage`, `make test-gitlab`, `make test-resilience` завершились без ошибок.
