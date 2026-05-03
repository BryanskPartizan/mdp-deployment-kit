# Обращение в поддержку Yandex Cloud по PermissionDenied в VPC

Тема: PermissionDenied при создании external address и добавлении ingress rule в security group, несмотря на admin/vpc роли

Здравствуйте.

Прошу помочь разобраться с ошибками доступа в Yandex Cloud. При разворачивании инфраструктуры через Terraform service account получает `PermissionDenied` на операции VPC, хотя роли на folder/cloud/organization выданы и `access-analyzer` их видит.

## Контекст

Разворачиваю Kubernetes deployment-kit в Yandex Cloud через Terraform. Используется self-hosted kubeadm-кластер. Terraform создаёт VPC, subnet, security group, VM, static external addresses и Network Load Balancer.

Ошибка воспроизводится не только через Terraform, но и прямыми командами `yc`, поэтому проблема, похоже, не в Terraform provider и не в Terraform-модулях.

## Идентификаторы ресурсов

Organization:

```text
organization_id: bpfpfcq1irm567kd6akg
organization_name: s3xk5lm9et19aqh8
```

Cloud:

```text
cloud_id: b1g5h2eidfj5nvj9m691
cloud_name: cloud-mdpavlyutin
```

Folder:

```text
folder_id: b1gsetoo8rdt9uhavi9d
folder_name: deployment-kit-dev
zone: ru-central1-a
```

Пользователь, от имени которого выполнялась настройка:

```text
subject_id: ajemfmj56bs53ku1hacs
username: MDPavlyutin@ya.ru
```

Service account, созданный для Terraform:

```text
service_account_name: dk-terraform-20260429-2023
service_account_id: aje9c4rapu8ljdh7ir6m
folder_id: b1gsetoo8rdt9uhavi9d
created_at: 2026-04-29T17:23:59Z
```

VPC network, в которой проверялась security group:

```text
network_id: enpp1rdktl66hns4og40
network_name: mdp-k8s-dev-network
```

## Версии инструментов

```text
OS/arch: macOS, darwin_arm64
Yandex Cloud CLI: 1.6.0 darwin/arm64
Terraform: v1.14.9 darwin_arm64
Terraform provider: registry.terraform.io/yandex-cloud/yandex 0.201.0
```

Terraform provider скачивался через официальное зеркало:

```text
https://terraform-mirror.yandexcloud.net/
```

## Как настраивался service account

Настройка выполнялась из административного CLI-профиля пользователя `MDPavlyutin@ya.ru`.

Был создан новый service account:

```bash
export YC_TERRAFORM_SA_NAME="dk-terraform-20260429-2023"

yc iam service-account create \
  --name "$YC_TERRAFORM_SA_NAME" \
  --folder-id "$YC_FOLDER_ID"
```

Результат:

```text
id: aje9c4rapu8ljdh7ir6m
folder_id: b1gsetoo8rdt9uhavi9d
created_at: "2026-04-29T17:23:59Z"
name: dk-terraform-20260429-2023
```

На folder были выданы роли:

```text
admin
compute.admin
vpc.admin
vpc.publicAdmin
vpc.securityGroups.admin
load-balancer.admin
dns.editor
cdn.editor
certificate-manager.editor
```

На cloud были выданы роли:

```text
admin
resource-manager.viewer
quota-manager.viewer
quota-manager.requestOperator
```

На organization были выданы роли:

```text
admin
organization-manager.viewer
```

Пользователю `ajemfmj56bs53ku1hacs` была выдана роль `iam.serviceAccounts.tokenCreator` на service account:

```text
service_account_id: aje9c4rapu8ljdh7ir6m
role_id: iam.serviceAccounts.tokenCreator
subject_id: ajemfmj56bs53ku1hacs
```

Terraform запускался через IAM token, выпущенный impersonation-командой:

```bash
export YC_TOKEN="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
export YC_CLOUD_ID="$(yc config get cloud-id)"
export YC_FOLDER_ID="$(yc config get folder-id)"
export TF_VAR_yc_token="$YC_TOKEN"
```

Токены и private keys в обращение не включаю.

## Что показывает access analyzer

Команда:

```bash
yc --profile default iam access-analyzer list-subject-access-bindings \
  --organization-id bpfpfcq1irm567kd6akg \
  --subject-id aje9c4rapu8ljdh7ir6m \
  --format json | jq -r '.[] | [.resource.type,.resource.id,.role_id] | @tsv' | sort
```

Результат:

```text
organization-manager.organization  bpfpfcq1irm567kd6akg  admin
organization-manager.organization  bpfpfcq1irm567kd6akg  organization-manager.viewer
resource-manager.cloud             b1g5h2eidfj5nvj9m691  admin
resource-manager.cloud             b1g5h2eidfj5nvj9m691  quota-manager.requestOperator
resource-manager.cloud             b1g5h2eidfj5nvj9m691  quota-manager.viewer
resource-manager.cloud             b1g5h2eidfj5nvj9m691  resource-manager.viewer
resource-manager.folder            b1gsetoo8rdt9uhavi9d  admin
resource-manager.folder            b1gsetoo8rdt9uhavi9d  cdn.editor
resource-manager.folder            b1gsetoo8rdt9uhavi9d  certificate-manager.editor
resource-manager.folder            b1gsetoo8rdt9uhavi9d  compute.admin
resource-manager.folder            b1gsetoo8rdt9uhavi9d  dns.editor
resource-manager.folder            b1gsetoo8rdt9uhavi9d  load-balancer.admin
resource-manager.folder            b1gsetoo8rdt9uhavi9d  vpc.admin
resource-manager.folder            b1gsetoo8rdt9uhavi9d  vpc.publicAdmin
resource-manager.folder            b1gsetoo8rdt9uhavi9d  vpc.securityGroups.admin
```

## Ошибка при Terraform apply

Terraform создаёт subnet, после чего падает на security group и static external addresses.

Фрагмент ошибки:

```text
module.firewall.yandex_vpc_security_group.this: Creating...

Error: error while requesting API to create security group:
rpc error: code = PermissionDenied desc = Permission denied to add ingress rule to security group

with module.firewall.yandex_vpc_security_group.this,
on ../modules/firewall/main.tf line 2, in resource "yandex_vpc_security_group" "this"
```

Trace/request IDs из Terraform:

```text
client-request-id: 23ca311b-9273-4dde-b6f9-0882ede37ccb
client-trace-id:   d1cd778d-6ea1-4d29-aa23-f06b3f4fb95d
operation:         create security group with ingress rules
error:             Permission denied to add ingress rule to security group
```

Также Terraform падает на static external addresses:

```text
client-request-id: 3d1fe00c-2843-4559-b339-feee5bf84b58
client-trace-id:   d1cd778d-6ea1-4d29-aa23-f06b3f4fb95d
operation:         create external address for api
error:             Permission denied to create external address
```

```text
client-request-id: c7a34c21-be58-42e2-87ba-52d6b4ece7dd
client-trace-id:   d1cd778d-6ea1-4d29-aa23-f06b3f4fb95d
operation:         create external address for ingress
error:             Permission denied to create external address
```

## Прямое воспроизведение через yc CLI

Чтобы исключить проблему Terraform, были выполнены прямые проверки через `yc` с impersonation нового service account `aje9c4rapu8ljdh7ir6m`.

### 1. Создание static external address

Команда:

```bash
yc --profile default \
  --impersonate-service-account-id aje9c4rapu8ljdh7ir6m \
  vpc address create \
  --name dk-support-test-ip-new-sa \
  --folder-id b1gsetoo8rdt9uhavi9d \
  --external-ipv4 zone=ru-central1-a
```

Результат:

```text
ERROR: rpc error: code = PermissionDenied desc = Permission denied to create external address

client-request-id: 89474d36-ac9e-4fdf-ba6a-cdb4e1213246
client-trace-id:   1e6403f0-cffb-40d1-bed8-7ce244f52f36
```

Trace-файл на локальной машине:

```text
/Users/mdpavlyutin/.config/yandex-cloud/logs/2026-04-29T21-04-14.726-yc_vpc_address_create.txt
```

### 2. Создание пустой security group

Команда:

```bash
yc --profile default \
  --impersonate-service-account-id aje9c4rapu8ljdh7ir6m \
  vpc security-group create \
  --name dk-support-test-sg-new-sa \
  --network-id enpp1rdktl66hns4og40 \
  --folder-id b1gsetoo8rdt9uhavi9d \
  --format json
```

Результат: пустая security group успешно создалась.

```text
created_security_group_id: enp3c0po589qga5jefiu
```

После теста security group была удалена.

### 3. Добавление ingress rule в созданную security group

Команда:

```bash
yc --profile default \
  --impersonate-service-account-id aje9c4rapu8ljdh7ir6m \
  vpc security-group update-rules enp3c0po589qga5jefiu \
  --add-rule direction=ingress,port=22,protocol=tcp,v4-cidrs=10.10.10.0/24 \
  --folder-id b1gsetoo8rdt9uhavi9d
```

Результат:

```text
ERROR: rpc error: code = PermissionDenied desc = Permission denied to add ingress rule to security group

client-request-id: 440ae1be-8e15-456a-915b-78f3a4aebf23
client-trace-id:   fdf0f988-ce77-4367-a8a5-ca3d79ae9484
```

Trace-файл на локальной машине:

```text
/Users/mdpavlyutin/.config/yandex-cloud/logs/2026-04-29T21-04-47.588-yc_vpc_security-group_update-rules_enp3c0po589qga5jefiu.txt
```

Важно: правило было не на публичный CIDR, а на внутреннюю сеть `10.10.10.0/24`. То есть ошибка возникает не только на публичные ingress rules.

### 4. Дополнительная проверка от пользовательского профиля

Проверка создания external address от пользовательского профиля `default`, у которого есть `resource-manager.clouds.owner` на cloud и `organization-manager.organizations.owner` на organization, также завершилась `PermissionDenied`.

Trace/request IDs:

```text
client-request-id: d0e33f70-1801-4939-a048-5ecb99c8275b
client-trace-id:   8329b371-e121-4ddf-bc8f-8e38896ef16f
operation:         create external address from default user profile
error:             Permission denied to create external address
```

Trace-файл:

```text
/Users/mdpavlyutin/.config/yandex-cloud/logs/2026-04-29T20-57-41.299-yc_vpc_address_create.txt
```

## Ожидаемое поведение

Service account с ролями `admin`, `vpc.admin`, `vpc.publicAdmin`, `vpc.securityGroups.admin` на нужном folder, а также `admin` на cloud и organization, должен иметь возможность:

1. Создать static external IPv4 address в folder `b1gsetoo8rdt9uhavi9d`.
2. Добавить ingress rule в security group внутри VPC network `enpp1rdktl66hns4og40`.

## Фактическое поведение

1. Пустая security group создаётся успешно.
2. Добавление ingress rule в security group завершается `PermissionDenied`.
3. Создание static external IPv4 address завершается `PermissionDenied`.
4. Ошибка воспроизводится прямыми командами `yc`, без Terraform.

## Что прошу проверить

Прошу проверить на стороне Yandex Cloud:

1. Есть ли на organization/cloud/folder политики, ограничения или внутренние блокировки, запрещающие:
   - создание external static IPv4 addresses;
   - добавление ingress rules в security groups.
2. Есть ли ограничения, связанные с публичной сетевой связностью, security groups или external IP для данного cloud/folder.
3. Почему `access-analyzer` показывает достаточные роли, но фактические VPC API calls возвращают `PermissionDenied`.
4. Нужны ли дополнительные роли или включение каких-либо сервисов/разрешений, не отражённые в стандартных IAM roles.

Готов приложить trace-файлы из локального каталога Yandex Cloud CLI logs.

