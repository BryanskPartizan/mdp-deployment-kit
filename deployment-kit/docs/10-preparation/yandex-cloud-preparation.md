# Подготовка Yandex Cloud перед запуском

Документ описывает действия, которые нужно выполнить в Yandex Cloud до первого запуска `make infra-plan` и `make infra-apply`. Команды ниже выполняются на машине оператора, с которой будет запускаться deployment-kit.

Последняя сверка с официальной документацией Yandex Cloud: 29 апреля 2026.

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

## 3. Установить Terraform и инициализировать Yandex Cloud CLI

Официальный quickstart для macOS использует Homebrew:

```bash
brew install terraform
terraform version
```

Если Terraform уже установлен, достаточно проверить версию. В проекте требуется Terraform `>= 1.7.0`.

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

Для загрузки Yandex Cloud provider настройте Terraform mirror, как в официальной инструкции:

```bash
mkdir -p ~/.terraform.d/plugin-cache
test -f ~/.terraformrc && cp ~/.terraformrc ~/.terraformrc.backup.$(date +%Y%m%d%H%M%S)

cat > ~/.terraformrc <<'EOF'
plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"

provider_installation {
  network_mirror {
    url = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
EOF
```

Если пересоздаёте `.terraform.lock.hcl` на macOS, фиксируйте provider hashes под нужные платформы:

```bash
terraform -chdir=terraform/vm providers lock \
  -net-mirror=https://terraform-mirror.yandexcloud.net \
  -platform=darwin_arm64 \
  -platform=linux_amd64 \
  yandex-cloud/yandex
```

## 4. Создать новый service account и сразу выдать права

Рекомендуемая модель: Terraform запускается не от личного пользователя, а от отдельного service account. Если предыдущая попытка подготовки уже создавала `dk-terraform`, не переиспользуйте его: создайте новый account с уникальным именем и начните с чистого набора ролей.

Все команды в этом разделе выполняются из административного CLI-профиля пользователя, который имеет право управлять IAM на нужном cloud/folder:

```bash
yc config profile activate default
yc config set cloud-id "$YC_CLOUD_ID"
yc config set folder-id "$YC_FOLDER_ID"
```

Создайте новый service account:

```bash
export YC_TERRAFORM_SA_NAME="dk-terraform-$(date +%Y%m%d-%H%M)"

yc iam service-account create \
  --name "$YC_TERRAFORM_SA_NAME" \
  --folder-id "$YC_FOLDER_ID"
```

Получите его ID:

```bash
export YC_TERRAFORM_SA_ID="$(
  yc iam service-account list \
    --folder-id "$YC_FOLDER_ID" \
    --format json | jq -r ".[] | select(.name==\"${YC_TERRAFORM_SA_NAME}\") | .id"
)"

test -n "$YC_TERRAFORM_SA_ID"
echo "$YC_TERRAFORM_SA_NAME -> $YC_TERRAFORM_SA_ID"
```

Для первого запуска deployment-kit выдайте все проектные роли одним блоком. Это bootstrap-модель с широкими правами на уровне folder/cloud; после успешного деплоя её можно сузить.

```bash
for role in \
  admin \
  compute.admin \
  vpc.admin \
  vpc.publicAdmin \
  vpc.securityGroups.admin \
  load-balancer.admin \
  dns.editor \
  cdn.editor \
  certificate-manager.editor
do
  yc resource-manager folder add-access-binding "$YC_FOLDER_ID" \
    --role "$role" \
    --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
done

for role in \
  admin \
  resource-manager.viewer \
  quota-manager.viewer \
  quota-manager.requestOperator
do
  yc resource-manager cloud add-access-binding "$YC_CLOUD_ID" \
    --role "$role" \
    --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
done
```

Проверьте, что роли видны:

```bash
yc resource-manager folder list-access-bindings "$YC_FOLDER_ID" \
  --format json | jq -r ".[] | select(.subject.id == \"${YC_TERRAFORM_SA_ID}\") | .role_id" | sort

yc resource-manager cloud list-access-bindings "$YC_CLOUD_ID" \
  --format json | jq -r ".[] | select(.subject.id == \"${YC_TERRAFORM_SA_ID}\") | .role_id" | sort
```

### Org-level права только при необходимости

В нормальном случае прав на folder/cloud достаточно. Если даже после `admin` на folder/cloud прямой тест `yc vpc address create` от service account возвращает `PermissionDenied`, значит в организации может действовать политика, которая требует org-level прав или отдельного разрешения владельца организации.

Этот блок расширяет blast radius на всю организацию. Выполняйте его только если вы осознанно принимаете такой риск для bootstrap-стенда:

```bash
export YC_ORG_ID="<organization_id>"

yc organization-manager organization add-access-binding "$YC_ORG_ID" \
  --role admin \
  --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"

yc organization-manager organization add-access-binding "$YC_ORG_ID" \
  --role organization-manager.viewer \
  --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
```

После успешного первого деплоя вернитесь к least-privilege модели: оставьте только роли, которые реально нужны выбранным Terraform-слоям.

## 5. Подготовить аутентификацию Terraform

Текущий Terraform provider в проекте ожидает IAM token через переменную `TF_VAR_yc_token`.

### Вариант A. Impersonation service account

Это предпочтительный вариант для локального запуска: пользователь остаётся аутентифицирован в CLI, но операции Terraform выполняются токеном service account.

Пользователь или CI principal должен иметь роль `iam.serviceAccounts.tokenCreator` на новом service account из `YC_TERRAFORM_SA_ID`.

Назначить роль можно через IAM UI или CLI:

```bash
yc iam service-account add-access-binding "$YC_TERRAFORM_SA_ID" \
  --role iam.serviceAccounts.tokenCreator \
  --subject "userAccount:<user_account_id>"
```

Получить IAM token:

```bash
export YC_TOKEN="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
export YC_CLOUD_ID="$(yc config get cloud-id)"
export YC_FOLDER_ID="$(yc config get folder-id)"
export TF_VAR_yc_token="$YC_TOKEN"
```

Официальный Terraform quickstart использует `YC_TOKEN`, `YC_CLOUD_ID` и `YC_FOLDER_ID`. Deployment-kit дополнительно экспортирует `TF_VAR_yc_token`, потому что текущий provider block получает token через Terraform variable `yc_token`.

IAM token живёт ограниченное время. Перед долгим `terraform plan/apply` лучше выпускать новый токен.

### Вариант B. Authorized key service account

Этот вариант удобен для CI, но требует аккуратного хранения long-lived key.

Создайте локальный каталог для ключей:

```bash
mkdir -p .secrets
chmod 700 .secrets
test -f .secrets/yc-dk-terraform-key.json && \
  mv .secrets/yc-dk-terraform-key.json ".secrets/yc-dk-terraform-key.$(date +%Y%m%d%H%M%S).json"
```

Создайте authorized key для нового service account:

```bash
yc iam key create \
  --service-account-id "$YC_TERRAFORM_SA_ID" \
  --output .secrets/yc-dk-terraform-key.json \
  --folder-id "$YC_FOLDER_ID"

chmod 600 .secrets/yc-dk-terraform-key.json
```

Создайте или обновите отдельный CLI profile:

```bash
yc config profile create dk-terraform-sa || yc config profile activate dk-terraform-sa
yc config set service-account-key .secrets/yc-dk-terraform-key.json
yc config set cloud-id "$YC_CLOUD_ID"
yc config set folder-id "$YC_FOLDER_ID"
```

Получите IAM token для Terraform:

```bash
export YC_TOKEN="$(yc iam create-token)"
export YC_CLOUD_ID="$(yc config get cloud-id)"
export YC_FOLDER_ID="$(yc config get folder-id)"
export TF_VAR_yc_token="$YC_TOKEN"
```

Файл `.secrets/yc-dk-terraform-key.json` не должен попадать в Git.

## 6. Проверить квоты

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

Проверка квот не обязательна для работы Terraform, но сильно снижает риск падения `apply` в середине создания ресурсов. В clean-start блоке выше service account уже получает `quota-manager.viewer`, `quota-manager.requestOperator` и `resource-manager.viewer` на уровне cloud. Если проверяете квоты из личного профиля, у пользователя должны быть аналогичные права или admin/editor на cloud.

Сначала посмотрите фактические service IDs, доступные в вашем cloud:

```bash
yc quota-manager quota-limit list-services \
  --resource-type resource-manager.cloud
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
  --service ylb \
  --resource-type resource-manager.cloud \
  --resource-id "$YC_CLOUD_ID"
```

Критичные quota IDs, которые стоит проверить в выводе:

```text
compute.instances.count
compute.instanceCores.count
compute.instanceMemory.size
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

## 7. Подготовить SSH-ключ

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

## 8. Выбрать CIDR и доступы

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

## 9. Проверить образ Ubuntu и зону

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

## 10. Подготовить DNS-решение

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
<INGRESS_IP> app.pkhco.ru gateway.pkhco.ru api.pkhco.ru gitlab.pkhco.ru registry.pkhco.ru minio.pkhco.ru
```

Для текущего публичного профиля используйте реальные Cloudflare DNS-записи `pkhco.ru`; hosts-файл остаётся только диагностическим fallback для `curl --resolve`.

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

Подробная модель доменов, TLS и CDN описана в `docs/10-preparation/domain-cdn.md`.

## 11. Проверить исходящий доступ с будущих VM

По умолчанию `enable_nat = true`, поэтому VM получают внешний NAT-адрес и смогут скачивать пакеты Ubuntu, containerd, Kubernetes packages и контейнерные образы.

Если вы выключаете `enable_nat`, заранее подготовьте один из вариантов:

- NAT gateway и route table;
- корпоративный egress proxy;
- зеркала apt/container registry внутри сети;
- bastion/proxy с маршрутизацией.

Без исходящего доступа Ansible bootstrap и Helm deployment не завершатся.

## 12. Заполнить файлы deployment-kit

Заполните `environments/vm-dev/terraform.tfvars`:

```hcl
yc_cloud_id         = "<cloud_id>"
yc_folder_id        = "<folder_id>"
yc_zone             = "ru-central1-a"
ssh_public_key_path = "/absolute/path/to/dk-yc-ed25519.pub"
allowed_ssh_cidrs   = ["<your_public_ip>/32"]
allowed_api_cidrs   = ["<your_public_ip>/32"]
```

Заполните `environments/vm-dev/edge.tfvars`: `yc_cloud_id`, `yc_folder_id`, `yc_zone` и `cluster_name` должны соответствовать основному окружению. Для текущего публичного профиля используйте `domain_name = "pkhco.ru"`, `dns_provider = "cloudflare"`, `dns_mode = "public"` и `cdn_enabled = false`.

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
APP_DOMAIN=pkhco.ru
TLS_CLUSTER_ISSUER=letsencrypt-prod
LETSENCRYPT_EMAIL=<admin_email>
TF_VAR_cloudflare_zone_id=<cloudflare_zone_id>
TF_VAR_cloudflare_api_token=<cloudflare_dns_token>
TF_VAR_app_secret_overrides='<json>'
```

Загрузите переменные:

```bash
set -a
source .env
set +a
```

## 13. Финальный preflight перед скриптами

Из каталога `deployment-kit`:

```bash
terraform version
yc config list
test -n "${YC_TOKEN:-}"
test -n "${TF_VAR_yc_token:-}"
test -f "$(grep ssh_public_key_path environments/vm-dev/terraform.tfvars | awk -F'"' '{print $2}')"
make validate ENV=vm-dev
```

После этого можно запускать:

```bash
make infra-plan ENV=vm-dev
make infra-apply ENV=vm-dev
```

## 14. Частые ошибки подготовки

### `Quota limit ylb.networkLoadBalancers.count exceeded`

В облаке нет свободных квот на NLB. Для `vm-dev` нужны 2 NLB. Удалите старые балансировщики или увеличьте квоту.

### `Quota limit vpc.externalStaticAddresses.count exceeded`

Для API и ingress резервируются 2 статических публичных IP. Если квота уже занята, удалите старые static IP или запросите увеличение.

### `Permission denied` от Terraform provider

Проверьте, что `TF_VAR_yc_token` выпущен именно для нового service account, созданного в разделе 4, а роли выданы единым bootstrap-блоком на нужный folder/cloud.

Быстрая проверка public IP от имени service account:

```bash
yc config profile activate dk-terraform-sa
export YC_TOKEN="$(yc iam create-token)"
export TF_VAR_yc_token="$YC_TOKEN"

yc vpc address create \
  --name dk-permission-test-ip \
  --folder-id "$YC_FOLDER_ID" \
  --external-ipv4 "zone=${YC_ZONE:-ru-central1-a}"

yc vpc address delete \
  --name dk-permission-test-ip \
  --folder-id "$YC_FOLDER_ID"
```

Если прямой `yc vpc address create` возвращает `PermissionDenied`, проблема не в Terraform. Проверьте организационные политики или выполните org-level блок из раздела 4.

Если роли уже выданы, проверьте итоговый доступ через access analyzer:

```bash
export YC_ORG_ID="<organization_id>"

yc iam access-analyzer list-subject-access-bindings \
  --organization-id "$YC_ORG_ID" \
  --subject-id "$YC_TERRAFORM_SA_ID" \
  --format json | jq -r '.[] | [.resource.type, .resource.id, .role_id] | @tsv' | sort
```

Если access analyzer показывает `admin`, `vpc.admin`, `vpc.publicAdmin` и `vpc.securityGroups.admin` на нужных resource-manager cloud/folder, но прямые команды `yc vpc address create` или `yc vpc security-group update-rules` всё равно возвращают `PermissionDenied`, это уже не ошибка deployment-kit. Такой результат означает ограничение на уровне Yandex Cloud organization/cloud или внутренней политики провайдера. В этом случае сохраните `client-request-id`, `client-trace-id` и trace-файл из ошибки и передайте их в поддержку Yandex Cloud.

### `IAM token is expired`

IAM token ограничен по времени. Выпустите новый:

```bash
# Если используется Variant B с authorized key:
yc config profile activate dk-terraform-sa
export YC_TOKEN="$(yc iam create-token)"
export TF_VAR_yc_token="$YC_TOKEN"

# Если используется Variant A с impersonation:
export YC_TOKEN="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
export TF_VAR_yc_token="$YC_TOKEN"
```

### Ansible не может подключиться по SSH

Проверьте:

- `ssh_public_key_path` указывает на публичный ключ;
- приватный ключ есть у оператора;
- `allowed_ssh_cidrs` содержит текущий внешний IP;
- VM получили public NAT, если подключение идёт напрямую;
- пользователь `ssh_user` совпадает с metadata VM, по умолчанию `ubuntu`.

## 15. Официальные ссылки

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
