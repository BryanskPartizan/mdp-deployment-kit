# Этап 1. Подготовка Yandex Cloud и учетных данных

## Назначение этапа

Цель этапа — подготовить облачное окружение, в котором deployment-kit сможет создавать
инфраструктуру через Terraform: выбрать облако, создать каталог, создать сервисный аккаунт,
выдать ему необходимые права, подготовить ключ сервисного аккаунта, SSH-ключ и локальный `.env`.

<span style="color:#16833a"><strong>Итог этапа:</strong></span> облако и каталог подготовлены,
сервисный аккаунт `dk-terraform` создан, локальная аутентификация Terraform настроена.

## 1.1. Проверка доступного облака

### Команда

```bash
yc resource-manager cloud list
```

### Зачем запускалась

Команда нужна для определения доступного Yandex Cloud cloud-id и проверки, что CLI авторизован
под корректной учетной записью.

### Вывод

```text
+----------------------+-------------------+----------------------+--------+
|          ID          |       NAME        |   ORGANIZATION ID    | LABELS |
+----------------------+-------------------+----------------------+--------+
| b1g5h2eidfj5nvj9m691 | cloud-mdpavlyutin | bpfpfcq1irm567kd6akg |        |
+----------------------+-------------------+----------------------+--------+
```

## 1.2. Проверка текущего профиля Yandex Cloud CLI

### Команда

```bash
yc config list
```

### Зачем запускалась

Команда фиксирует текущего пользователя CLI. Это важно для последующего разграничения действий:
права на каталог выдаются административным профилем, а Terraform работает через сервисный аккаунт.

### Вывод

```text
subject-id: ajemfmj56bs53ku1hacs
username: MDPavlyutin@ya.ru
```
## 1.3. Создание каталога для стенда

### Команда

```bash
yc resource-manager folder create --name deployment-kit-dev
```

### Зачем запускалась

Каталог изолирует ресурсы стенда `vm-dev`: сеть, подсеть, ВМ, балансировщики, адреса, DNS-ресурсы
и права сервисного аккаунта.

### Вывод

```text
done (2s)
id: <folder_id>
cloud_id: <cloud_id>
created_at: "2026-04-28T15:18:15Z"
name: deployment-kit-dev
status: ACTIVE
```

## 1.4. Экспорт идентификаторов облака и каталога

### Команды

```bash
export YC_CLOUD_ID="<cloud_id>"
export YC_FOLDER_ID="<folder_id>"
```

### Зачем запускались

Переменные используются в последующих командах `yc`, Makefile-сценариях и Terraform.
Значения скрыты как параметры окружения стенда.

## 1.5. Создание сервисного аккаунта Terraform

### Команда

```bash
yc iam service-account create \
  --name dk-terraform \
  --folder-id "$YC_FOLDER_ID"
```

### Зачем запускалась

Terraform не должен работать от имени личного пользователя. Сервисный аккаунт нужен для
воспроизводимого и ограничиваемого доступа к инфраструктурным API Yandex Cloud.

### Вывод

```text
done (2s)
id: ajeqiufb6o5sqbi2rvjt
folder_id: b1gsetoo8rdt9uhavi9d
created_at: "2026-04-28T15:23:37Z"
name: dk-terraform
```

## 1.6. Получение id сервисного аккаунта

### Команда

```bash
export YC_TERRAFORM_SA_ID="$(
  yc iam service-account list \
    --folder-id "$YC_FOLDER_ID" \
    --format json | jq -r '.[] | select(.name=="dk-terraform") | .id'
)"

echo "$YC_TERRAFORM_SA_ID"
```

### Зачем запускалась

Id сервисного аккаунта нужен для выдачи IAM ролей и создания ключа.

### Вывод

```text
ajeqiufb6o5sqbi2rvjt
```

## 1.7. Выдача прав сервисному аккаунту

### Команды

```bash
for role in compute.admin vpc.admin load-balancer.admin; do
  yc resource-manager folder add-access-binding "$YC_FOLDER_ID" \
    --role "$role" \
    --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
done

for role in dns.editor cdn.editor certificate-manager.editor; do
  yc resource-manager folder add-access-binding "$YC_FOLDER_ID" \
    --role "$role" \
    --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"
done
```

### Зачем запускались

Роли позволяют Terraform создавать ресурсы, описанные в `terraform/vm` и `terraform/edge`.

| Роль | Для чего нужна |
| --- | --- |
| `compute.admin` | Создание и удаление виртуальных машин control plane и worker. |
| `vpc.admin` | Создание VPC, подсети и сетевых ресурсов. |
| `load-balancer.admin` | Создание Network Load Balancer для Kubernetes API и ingress. |
| `dns.editor` | Управление DNS-ресурсами при использовании Yandex Cloud DNS. |
| `cdn.editor` | Подготовка CDN-расширения edge-контура. |
| `certificate-manager.editor` | Работа с Certificate Manager при edge-расширениях. |

### Вывод

В полном журнале команды выдачи ролей не печатали расширенный объект для каждого вызова. 
Отсутствие ошибок на этом шаге означает успешное добавление access bindings.

## 1.8. Создание ключа сервисного аккаунта

### Команды

```bash
mkdir -p .secrets
chmod 700 .secrets

yc iam key create \
  --service-account-id "$YC_TERRAFORM_SA_ID" \
  --output .secrets/yc-dk-terraform-key.json \
  --folder-id "$YC_FOLDER_ID"

chmod 600 .secrets/yc-dk-terraform-key.json
```

### Зачем запускались

Ключ сервисного аккаунта используется локальным профилем `yc` и Terraform-токенами. Файл помещен в
`.secrets`, права на каталог и ключ ограничены.

### Вывод

Содержимое ключа в отчет не переносится, так как это секретный материал. Факт успешного выполнения
подтверждается дальнейшим созданием профиля и успешными Terraform-командами.

## 1.9. Создание CLI-профиля сервисного аккаунта

### Команды

```bash
yc config profile create dk-terraform-sa
yc config set service-account-key .secrets/yc-dk-terraform-key.json
yc config set cloud-id "$YC_CLOUD_ID"
yc config set folder-id "$YC_FOLDER_ID"
```

### Зачем запускались

Профиль `dk-terraform-sa` переключает CLI на сервисный аккаунт Terraform и задает контекст облака и
каталога.

## 1.10. Подготовка Terraform token

### Команды

```bash
export TF_VAR_yc_token="$(yc iam create-token)"

yc config profile activate default
yc resource-manager cloud add-access-binding "$YC_CLOUD_ID" \
  --role quota-manager.viewer \
  --subject "serviceAccount:${YC_TERRAFORM_SA_ID}"

yc config profile activate dk-terraform-sa
export TF_VAR_yc_token="$(yc iam create-token)"
```

### Зачем запускались

`TF_VAR_yc_token` передает Terraform IAM token через стандартный механизм переменных. Роль
`quota-manager.viewer` выдана для просмотра квот на уровне облака.

### Вывод

Значения токенов скрыты. В журнале токены не выводились явно, что соответствует требованиям
безопасности.

## 1.11. Проверка квот

### Команды

```bash
yc quota-manager quota-limit list-services \
  --resource-type resource-manager.cloud

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

### Зачем запускались

Команды нужны для проверки лимитов Compute, VPC и Yandex Load Balancer перед созданием 5 ВМ,
публичных адресов и балансировщиков.

## 1.12. Создание SSH-ключа для ВМ

### Команды

```bash
ssh-keygen -t ed25519 -f ~/.ssh/dk-yc-ed25519 -C "deployment-kit-yc"
chmod 600 ~/.ssh/dk-yc-ed25519
chmod 644 ~/.ssh/dk-yc-ed25519.pub
```

### Зачем запускались

SSH-ключ используется Terraform для metadata `ssh-keys` и Ansible для подключения к созданным ВМ.

### Вывод

Приватный ключ в отчет не переносится. Публичный ключ позднее виден в Terraform plan как metadata
для пользователя `ubuntu`.

## 1.13. Настройка `.env`

### Команды

```bash
cp .env.example .env
chmod 600 .env

set -a
source .env
set +a
```

### Зачем запускались

`.env` содержит локальные параметры запуска, домены, токены, режимы демо-секретов и настройки
интеграций. Права `600` ограничивают чтение файла текущим пользователем.

```text
mdpavlyutin@MDP deployment-kit % cp .env.example .env
mdpavlyutin@MDP deployment-kit % chmod 600 .env
```

## 1.14. Создание impersonated token

### Команды

```bash
export YC_TOKEN="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
export TF_VAR_yc_token="$YC_TOKEN"
```

### Зачем запускались

Команды формируют актуальный IAM token от имени сервисного аккаунта и передают его Terraform.

### Вывод

Токен скрыт как секрет. 


## Результат этапа

<span style="color:#16833a"><strong>Успешно.</strong></span> Подготовка Yandex Cloud и локальной
аутентификации завершена. Следующий этап — статическая проверка репозитория и Terraform plan.

