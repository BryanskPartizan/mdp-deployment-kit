# Этап 1. Подготовка облака и доступа

## Цель этапа

Подготовить Yandex Cloud для автоматизированного развертывания стенда: выбрать облако, создать
каталог, создать сервисный аккаунт Terraform и выдать ему права на управление сетями, ВМ,
балансировщиками, DNS/CDN и сертификатами.

## Выполненные действия

### Проверка доступных облаков

```bash
yc resource-manager cloud list
```

Значимый вывод:

```text
+----------------------+-------------------+----------------------+--------+
|          ID          |       NAME        |   ORGANIZATION ID    | LABELS |
+----------------------+-------------------+----------------------+--------+
| b1g5h2eidfj5nvj9m691 | cloud-mdpavlyutin | bpfpfcq1irm567kd6akg |        |
+----------------------+-------------------+----------------------+--------+
```

### Создание каталога

```bash
yc resource-manager folder create --name deployment-kit-dev
```

Значимый вывод:

```text
done (2s)
name: deployment-kit-dev
status: ACTIVE
```

### Создание сервисного аккаунта Terraform

```bash
yc iam service-account create \
  --name dk-terraform \
  --folder-id "$YC_FOLDER_ID"
```

Значимый вывод:

```text
done (2s)
id: ajeqiufb6o5sqbi2rvjt
name: dk-terraform
```

### Выдача ролей сервисному аккаунту

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

Права нужны для создания:

| Группа прав | Использование |
| --- | --- |
| `compute.admin` | Виртуальные машины control plane и worker. |
| `vpc.admin`, `vpc.publicAdmin`, `vpc.securityGroups.admin` | VPC, подсеть, security group, публичные адреса. |
| `load-balancer.admin` | Network Load Balancer для Kubernetes API и ingress. |
| `dns.editor`, `cdn.editor`, `certificate-manager.editor` | Управление смежными edge-ресурсами Yandex Cloud при необходимости. |

### Подготовка ключа сервисного аккаунта

```bash
mkdir -p .secrets
chmod 700 .secrets

yc iam key create \
  --service-account-id "$YC_TERRAFORM_SA_ID" \
  --output .secrets/yc-dk-terraform-key.json \
  --folder-id "$YC_FOLDER_ID"

chmod 600 .secrets/yc-dk-terraform-key.json
```

### Подготовка профиля CLI и переменных Terraform

```bash
yc config profile create dk-terraform-sa
yc config set service-account-key .secrets/yc-dk-terraform-key.json
yc config set cloud-id "$YC_CLOUD_ID"
yc config set folder-id "$YC_FOLDER_ID"

export YC_TOKEN="$(
  yc iam create-token \
    --impersonate-service-account-id "$YC_TERRAFORM_SA_ID"
)"
export TF_VAR_yc_token="$YC_TOKEN"
```

## Результат этапа

<span style="color:#16833a"><strong>Успешно.</strong></span> Подготовлен отдельный каталог
`deployment-kit-dev`, создан сервисный аккаунт `dk-terraform`, настроены CLI-профиль и локальные
переменные для дальнейшего запуска Terraform и Makefile-сценариев.

## Замечания

Первичная попытка получить список folder без заданного `cloud-id` завершилась ожидаемой ошибкой
валидации:

```text
ERROR: rpc error: code = InvalidArgument desc = Validation failed:
  - cloud_id: Field is required
```

После установки `cloud-id` работа продолжилась штатно.

