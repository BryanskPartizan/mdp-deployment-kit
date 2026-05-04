# Этап 2. Локальная проверка конфигурации

## Цель этапа

До создания инфраструктуры проверить, что репозиторий находится в согласованном состоянии:
Terraform-конфигурации валидны, Ansible playbooks читаются, базовые манифесты и Helm templates
могут быть обработаны локально.

## Выполненная команда

```bash
make validate ENV=vm-dev
```

## Значимый вывод

```text
./ci/scripts/validate-static.sh

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

## Что проверено

| Проверка | Назначение |
| --- | --- |
| Ansible syntax | Подтверждает корректность playbook-файлов bootstrap-сценария. |
| Terraform validate: `terraform/vm` | Проверяет инфраструктурный слой ВМ, сети, балансировщиков. |
| Terraform validate: `terraform/edge` | Проверяет edge/DNS слой. |
| Terraform validate: `terraform/platform` | Проверяет платформенные Kubernetes-ресурсы. |
| Terraform validate: `terraform/vault` | Проверяет конфигурацию Vault. |

## Результат этапа

<span style="color:#16833a"><strong>Успешно.</strong></span> Локальные проверки завершились без
ошибок. Конфигурация признана готовой к планированию и созданию инфраструктуры.

