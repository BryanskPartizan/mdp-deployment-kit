# Подготовка Yandex Cloud перед запуском

Документ описывает действия, которые нужно выполнить в Yandex Cloud до первого запуска `make infra-plan` и `make infra-apply`. Команды ниже выполняются на машине оператора, с которой будет запускаться deployment-kit.

Последняя сверка с официальной документацией Yandex Cloud: 28 апреля 2026.

## 1. Что Terraform будет создавать

Для окружения `vm-dev` по умолчанию Terraform создаёт:

- 1 VPC network;
- 1 subnet в зоне `ru-central1-a`;
- 1 security group;
- 3 control-plane VM;
- 2 worker VM;
- 5 boot disks;
- 2 статических публичных IP-адреса для NLB;
- 2 Yandex Network Load Balancer;
- 2 target groups;
- NAT-адреса для VM, если `enable_nat = true`.

Ресурсный профиль по умолчанию:

```text
control-plane: 3 x 2 vCPU, 4 GB RAM, 40 GB boot disk
worker:        2 x 4 vCPU, 8 GB RAM, 60 GB boot disk
total:         14 vCPU, 28 GB RAM, 240 GB boot disks
```

Важно: проект использует ровно 2 Network Load Balancer и 2 статических публичных IP. В новых или trial-облаках это часто равно дефолтной квоте, поэтому в облаке не должно быть других NLB/static IP, либо квоты нужно увеличить заранее.

## 2. Подготовить billing, cloud и folder

Перед технической настройкой проверьте:

- есть активный billing account;
- cloud привязан к billing account;
- есть отдельный folder под стенд, например `deployment-kit-dev`;
- у пользователя, который настраивает IAM, есть права администратора на folder/cloud.

Проверка через CLI:

```bash
yc resource-manager cloud list
yc resource-manager folder list
```

Если folder ещё не создан:

```bash
yc resource-manager folder create --name deployment-kit-dev
```

После создания сохраните ID:

```bash
export YC_CLOUD_ID="<cloud_id>"
export YC_FOLDER_ID="<folder_id>"

yc config set cloud-id "$YC_CLOUD_ID"
yc config set folder-id "$YC_FOLDER_ID"
```

При создании folder через web console не включайте default network, если она не нужна. Deployment-kit создаёт собственную VPC, а лишняя default network будет занимать квоту.

## 3. Установить и инициализировать Yandex Cloud CLI

Проверьте CLI:

```bash
yc version
yc config list
```

Если CLI ещё не настроен:

```bash
yc init
```

После инициализации убедитесь, что выбран правильный cloud/folder:

```bash
yc config get cloud-id
yc config get folder-id
```

## 4. Создать service account для Terraform

Рекомендуемая модель: Terraform запускается не от личного пользователя, а от отдельного service account.

Создайте service account:

```bash
yc iam service-account create \
  --name dk-terraform \
  --folder-id "$YC_FOLDER_ID"
```

Получите его ID:

```bash
export YC_TERRAFORM_SA_ID="$(
  yc iam service-account list \
    --folder-id "$YC_FOLDER_ID" \
    --format json | jq -r '.[] | select(.name=="dk-terraform") | .id'
)"

echo "$YC_TERRAFORM_SA_ID"
```

## 5. Выдать роли service account

Минимальный практичный набор ролей на folder:

```text
compute.admin
vpc.admin
load-balancer.admin
```

Назначение ролей:

```bash
for role in compute.admin vpc.admin load-balancer.admin; do
  yc resource-manager folder add-access-binding "$YC_FOLDER_ID" \
    --role "$role" \
    --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
done
```

Зачем нужны эти роли:

- `compute.admin` — создание VM, boot disks, сетевых интерфейсов и использование образа Ubuntu;
- `vpc.admin` — создание VPC, subnet, security group, публичных IP и внешней связности;
- `load-balancer.admin` — создание внешних Network Load Balancer и target groups.

Для лабораторного стенда можно выдать широкую роль `editor`, но для нормальной модели доступа лучше оставить сервисные роли выше.

Если включаете `terraform/edge` для публичного DNS/CDN, дополнительно понадобятся роли:

```text
dns.editor
cdn.editor
certificate-manager.editor
```

Назначить их можно так:

```bash
for role in dns.editor cdn.editor certificate-manager.editor; do
  yc resource-manager folder add-access-binding "$YC_FOLDER_ID" \
    --role "$role" \
    --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
done
```

Для дефолтного режима `dns_mode = "hosts"` эти роли не обязательны: edge-слой только сохраняет локальный hosts-файл.

## 6. Подготовить аутентификацию Terraform

Текущий Terraform provider в проекте ожидает IAM token через переменную `TF_VAR_yc_token`.

### Вариант A. Impersonation service account

Это предпочтительный вариант для локального запуска: пользователь остаётся аутентифицирован в CLI, но операции Terraform выполняются токеном service account.

Пользователь или CI principal должен иметь роль `iam.serviceAccounts.tokenCreator` на service account `dk-terraform`.

Назначить роль можно через IAM UI или CLI:

```bash
yc iam service-account add-access-binding "$YC_TERRAFORM_SA_ID" \
  --role iam.serviceAccounts.tokenCreator \
  --subject "userAccount:<user_account_id>"
```

Получить IAM token:

```bash
export TF_VAR_yc_token="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
```

IAM token живёт ограниченное время. Перед долгим `terraform plan/apply` лучше выпускать новый токен.

### Вариант B. Authorized key service account

Этот вариант удобен для CI, но требует аккуратного хранения long-lived key.

Создайте локальный каталог для ключей:

```bash
mkdir -p .secrets
chmod 700 .secrets
```

Создайте authorized key:

```bash
yc iam key create \
  --service-account-id "$YC_TERRAFORM_SA_ID" \
  --output .secrets/yc-dk-terraform-key.json \
  --folder-id "$YC_FOLDER_ID"

chmod 600 .secrets/yc-dk-terraform-key.json
```

Создайте отдельный CLI profile:

```bash
yc config profile create dk-terraform-sa
yc config set service-account-key .secrets/yc-dk-terraform-key.json
yc config set cloud-id "$YC_CLOUD_ID"
yc config set folder-id "$YC_FOLDER_ID"
```

Получите IAM token для Terraform:

```bash
export TF_VAR_yc_token="$(yc iam create-token)"
```

Файл `.secrets/yc-dk-terraform-key.json` не должен попадать в Git.

## 7. Проверить квоты

Для стандартного `vm-dev` проверьте, что в cloud достаточно свободных квот:

```text
Compute Cloud:
- минимум 5 VM;
- минимум 14 vCPU;
- минимум 28 GB RAM;
- минимум 240 GB boot disk quota.

Virtual Private Cloud:
- 1 свободная VPC network;
- 1 свободная subnet;
- 1 свободная security group;
- 2 свободных static public IP;
- минимум 7 total public IP, если enable_nat = true и создаётся 5 VM.

Network Load Balancer:
- 2 свободных network load balancer;
- 2 свободных target group.
```

Посмотреть квоты через CLI:

```bash
yc quota-manager quota-limit list \
  --service compute \
  --resource-type resource-manager.cloud \
  --resource-id "$YC_CLOUD_ID"

yc quota-manager quota-limit list \
  --service vpc \
  --resource-type resource-manager.cloud \
  --resource-id "$YC_CLOUD_ID"

yc quota-manager quota-limit list \
  --service load-balancer \
  --resource-type resource-manager.cloud \
  --resource-id "$YC_CLOUD_ID"
```

Критичные quota IDs, которые стоит проверить в выводе:

```text
compute.instances.count
compute.cores.count
compute.memory.size
compute.hddDisks.size
vpc.networks.count
vpc.subnets.count
vpc.securityGroups.count
vpc.externalAddresses.count
vpc.externalStaticAddresses.count
ylb.networkLoadBalancers.count
ylb.targetGroups.count
```

Если квоты уже заняты другими ресурсами, либо удалите лишние ресурсы, либо запросите увеличение квот до запуска Terraform.

## 8. Подготовить SSH-ключ

Ansible подключается к VM по SSH. Создайте отдельный ключ для стенда:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/dk-yc-ed25519 -C "deployment-kit-yc"
chmod 600 ~/.ssh/dk-yc-ed25519
chmod 644 ~/.ssh/dk-yc-ed25519.pub
```

В `environments/vm-dev/terraform.tfvars` укажите абсолютный путь к публичному ключу:

```hcl
ssh_public_key_path = "/Users/<user>/.ssh/dk-yc-ed25519.pub"
ssh_user            = "ubuntu"
```

Terraform передаёт публичный ключ в metadata VM через поле `ssh-keys`.

## 9. Выбрать CIDR и доступы

Проверьте `environments/vm-dev/terraform.tfvars`:

```hcl
yc_cloud_id       = "<cloud_id>"
yc_folder_id      = "<folder_id>"
yc_zone           = "ru-central1-a"
yc_region         = "ru-central1"
cluster_name      = "demo-k8s-dev"
vm_prefix         = "demo"
network_cidr      = "10.10.10.0/24"
node_count_cp     = 3
node_count_worker = 2

allowed_ssh_cidrs     = ["<your_public_ip>/32"]
allowed_api_cidrs     = ["<your_public_ip>/32"]
allowed_ingress_cidrs = ["<your_public_ip>/32"]

ingress_http_node_port  = 30080
ingress_https_node_port = 30443
```

Получить внешний IP оператора:

```bash
curl -4 ifconfig.me
```

Не оставляйте `0.0.0.0/0` для SSH и Kubernetes API, если стенд доступен из интернета. Для demo можно временно открыть ingress шире, но SSH/API лучше ограничивать вашим IP или корпоративным VPN.

В репозитории используется безопасный placeholder `203.0.113.10/32`; это TEST-NET адрес, который нужно заменить перед `make infra-plan`.

## 10. Проверить образ Ubuntu и зону

Проект по умолчанию использует:

```hcl
yc_zone      = "ru-central1-a"
image_family = "ubuntu-2204-lts"
platform_id  = "standard-v3"
```

Перед запуском проверьте, что зона и image family доступны:

```bash
yc compute zone list
yc compute image get-latest-from-family ubuntu-2204-lts --folder-id standard-images
```

Если в вашей организации запрещены отдельные зоны или платформы VM, поменяйте `yc_zone`/`platform_id` в `terraform.tfvars` до `make infra-plan`.

## 11. Подготовить DNS-решение

Для автоматических тестов публичная DNS-зона не обязательна: скрипты используют IP из `.artifacts/<env>/terraform-outputs.json` и `curl --resolve`.

Для браузерного доступа есть два варианта.

### Вариант A. Локальный `/etc/hosts` через edge-слой

После `make infra-apply` выполните:

```bash
make edge-apply ENV=vm-dev
cat .artifacts/vm-dev/hosts-file
```

Добавьте полученные строки локально:

```text
<INGRESS_IP> app.mdp gateway.mdp api.mdp gitlab.mdp registry.mdp minio.mdp
```

Этот вариант подходит для demo, потому что `mdp` не является нормальным публичным доменом.

### Вариант B. Реальный домен в Cloud DNS через Terraform

Если нужен доступ без `/etc/hosts`, используйте реальный домен, например `example.com`. В `environments/vm-dev/edge.tfvars` задайте:

```hcl
domain_name     = "example.com"
dns_mode        = "public"
create_dns_zone = true
cdn_enabled     = false
```

После `infra-apply` выполните:

```bash
make edge-apply ENV=vm-dev
```

Если zone создаётся в Yandex Cloud, делегируйте NS-записи домена у регистратора на NS-серверы созданной Cloud DNS zone.

Для Kubernetes ingress также задайте домен:

```bash
export APP_DOMAIN=example.com
```

Подробная модель доменов, TLS и CDN описана в `docs/domain-cdn.md`.

## 12. Проверить исходящий доступ с будущих VM

По умолчанию `enable_nat = true`, поэтому VM получают внешний NAT-адрес и смогут скачивать пакеты Ubuntu, containerd, Kubernetes packages и контейнерные образы.

Если вы выключаете `enable_nat`, заранее подготовьте один из вариантов:

- NAT gateway и route table;
- корпоративный egress proxy;
- зеркала apt/container registry внутри сети;
- bastion/proxy с маршрутизацией.

Без исходящего доступа Ansible bootstrap и Helm deployment не завершатся.

## 13. Заполнить файлы deployment-kit

Заполните `environments/vm-dev/terraform.tfvars`:

```hcl
yc_cloud_id         = "<cloud_id>"
yc_folder_id        = "<folder_id>"
yc_zone             = "ru-central1-a"
ssh_public_key_path = "/absolute/path/to/dk-yc-ed25519.pub"
allowed_ssh_cidrs   = ["<your_public_ip>/32"]
allowed_api_cidrs   = ["<your_public_ip>/32"]
```

Заполните `environments/vm-dev/edge.tfvars`: `yc_cloud_id`, `yc_folder_id`, `yc_zone` и `cluster_name` должны соответствовать основному окружению. Для стартового приватного режима оставьте `domain_name = "mdp"`, `dns_mode = "hosts"` и `cdn_enabled = false`.

Создайте `.env`:

```bash
cp .env.example .env
chmod 600 .env
```

Минимально заполните:

```bash
TF_VAR_yc_token=<iam_token>
GRAFANA_ADMIN_PASSWORD=<strong_password>
GITLAB_ROOT_PASSWORD=<strong_password>
POSTGRES_APP_PASSWORD=<strong_password>
POSTGRES_ADMIN_PASSWORD=<strong_password>
APP_DOMAIN=mdp
TLS_CLUSTER_ISSUER=test-selfsigned
TF_VAR_app_secret_overrides='<json>'
```

Загрузите переменные:

```bash
set -a
source .env
set +a
```

## 14. Финальный preflight перед скриптами

Из каталога `deployment-kit`:

```bash
terraform version
yc config list
yc iam create-token >/dev/null
test -f "$(grep ssh_public_key_path environments/vm-dev/terraform.tfvars | awk -F'"' '{print $2}')"
make validate ENV=vm-dev
```

После этого можно запускать:

```bash
make infra-plan ENV=vm-dev
make infra-apply ENV=vm-dev
```

## 15. Частые ошибки подготовки

### `Quota limit ylb.networkLoadBalancers.count exceeded`

В облаке нет свободных квот на NLB. Для `vm-dev` нужны 2 NLB. Удалите старые балансировщики или увеличьте квоту.

### `Quota limit vpc.externalStaticAddresses.count exceeded`

Для API и ingress резервируются 2 статических публичных IP. Если квота уже занята, удалите старые static IP или запросите увеличение.

### `Permission denied` от Terraform provider

Проверьте, что `TF_VAR_yc_token` выпущен именно для service account `dk-terraform`, а у service account есть роли `compute.admin`, `vpc.admin`, `load-balancer.admin` на нужный folder.

### `IAM token is expired`

IAM token ограничен по времени. Выпустите новый:

```bash
export TF_VAR_yc_token="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
```

### Ansible не может подключиться по SSH

Проверьте:

- `ssh_public_key_path` указывает на публичный ключ;
- приватный ключ есть у оператора;
- `allowed_ssh_cidrs` содержит текущий внешний IP;
- VM получили public NAT, если подключение идёт напрямую;
- пользователь `ssh_user` совпадает с metadata VM, по умолчанию `ubuntu`.

## 16. Официальные ссылки

- Yandex Cloud CLI install: https://yandex.cloud/en/docs/cli/operations/install-cli
- `yc init`: https://yandex.cloud/en/docs/cli/cli-ref/init
- Service accounts: https://yandex.cloud/en/docs/iam/operations/sa/create
- Service account authentication: https://yandex.cloud/en/docs/cli/operations/authentication/service-account
- Assigning roles: https://yandex.cloud/en/docs/iam/operations/roles/grant
- IAM token lifetime: https://yandex.cloud/en/docs/iam/concepts/authorization/iam-token
- Yandex Cloud quotas: https://yandex.cloud/en/docs/overview/concepts/quotas-limits
- Quota Manager CLI: https://yandex.cloud/en/docs/quota-manager/operations/list-quotas
- VPC access management: https://yandex.cloud/en/docs/vpc/security/
- Network Load Balancer access management: https://yandex.cloud/en/docs/network-load-balancer/security/
- Cloud DNS records: https://yandex.cloud/en/docs/dns/operations/resource-record-create
- Cloud DNS access management: https://yandex.cloud/en/docs/dns/security/
- Certificate Manager: https://yandex.cloud/en/docs/certificate-manager
- CDN resource Terraform: https://yandex.cloud/en/docs/terraform/resources/cdn_resource
