# Этап 2. Статическая проверка deployment-kit

## Назначение этапа

Перед созданием ресурсов необходимо проверить, что локальная конфигурация репозитория корректна:
Ansible playbooks читаются, Terraform-конфигурации валидны, провайдеры доступны, а базовые
манифесты и Helm values не содержат синтаксических ошибок.

<span style="color:#16833a"><strong>Итог этапа:</strong></span> статическая проверка прошла
успешно, после чего был выполнен переход к Terraform plan.

## 2.1. Запуск общей проверки

### Команда

```bash
make validate ENV=vm-dev
```

### Зачем запускалась

Команда является входной контрольной точкой runbook. Она запускает `ci/scripts/validate-static.sh`
и проверяет основные IaC/CM-слои без изменения инфраструктуры.

### Вывод

```text
./ci/scripts/validate-static.sh
Pulled: quay.io/jetstack/charts/cert-manager:v1.19.5
Digest: sha256:a28d06d429263fd1a547aa3239fe7d22f17ebf7e8dbdb14726e9433925ba2396

playbook: ansible/playbooks/site.yml

playbook: ansible/playbooks/reset-kubeadm.yml
Terraform providers уже установлены для terraform/vm, init пропущен.
Success! The configuration is valid.

Terraform providers уже установлены для terraform/edge, init пропущен.
Success! The configuration is valid.

Terraform providers уже установлены для terraform/platform, init пропущен.
Success! The configuration is valid.

Terraform providers уже установлены для terraform/vault, init пропущен.
Success! The configuration is valid.
```

## 2.2. Что именно подтвердил вывод

| Блок вывода | Значение |
| --- | --- |
| `Pulled: quay.io/jetstack/charts/cert-manager:v1.19.5` | Helm chart cert-manager доступен и может быть обработан локально. |
| `playbook: ansible/playbooks/site.yml` | Основной Ansible playbook синтаксически корректен. |
| `playbook: ansible/playbooks/reset-kubeadm.yml` | Reset-playbook для повторного bootstrap корректен. |
| `terraform/vm ... valid` | Инфраструктурный слой Yandex Cloud валиден. |
| `terraform/edge ... valid` | DNS/edge слой валиден. |
| `terraform/platform ... valid` | Платформенный Kubernetes/Vault release слой валиден. |
| `terraform/vault ... valid` | Настройка Vault auth, policies и KV валидна. |

## Результат этапа

<span style="color:#16833a"><strong>Успешно.</strong></span> Команда `make validate ENV=vm-dev`
завершилась без ошибок. Deployment-kit признан готовым к планированию инфраструктуры.

