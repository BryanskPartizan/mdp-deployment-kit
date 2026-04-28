# Модель тестирования

Deployment kit включает несколько категорий проверок, разделённых по риску и назначению.

Полная последовательность запуска проверок после развертывания стенда описана в `docs/runbook.md`.

## Статическая проверка
До live-запуска проверяется формат Terraform, shell syntax, Helm rendering, Grafana dashboard JSON, Ansible syntax и Terraform validate, включая `terraform/edge`.

Запуск:
```bash
make validate ENV=vm-dev
```

## Smoke-тестирование
Подтверждает доступность endpoint, публикацию через ingress и работу базовых health-check маршрутов.

По умолчанию внешние проверки используют приватный домен `mdp`. Если стенд опубликован на другом домене, задайте `APP_DOMAIN=<domain>` либо точечные переменные `SMOKE_FRONTEND_HOST`, `SMOKE_GATEWAY_HOST`, `GITLAB_HOST`, `GITLAB_REGISTRY_HOST`.

Запуск:
```bash
make test-smoke ENV=vm-dev
```

## Проверка сетевой связанности
Проверяет разрешённые маршруты frontend -> gateway, gateway -> API, API -> PostgreSQL/Redis, observability -> health/datastore probes, а также внешние точки входа Yandex Network Load Balancer. Для проверки используются временные диагностические Pod'ы с теми же labels, которые участвуют в `NetworkPolicy`.

Запуск:
```bash
make test-network ENV=vm-dev
```

## Проверка безопасности
Проверяет запреты `NetworkPolicy` и ожидаемые ограничения RBAC для прикладных ServiceAccount.

Запуск:
```bash
make test-security ENV=vm-dev
```

## Интеграционное тестирование
Проверяет rollout платформенных компонентов, наличие Grafana dashboards, PrometheusRule и blackbox ServiceMonitor, StatefulSet/Deployment прикладного контура, наличие Endpoints, HTTP health endpoints и полный путь Vault Agent Injector от Kubernetes ServiceAccount до injected secret file.
Тест Vault проверяет наличие ожидаемого ключа, но не печатает значение секрета в logs.

Запуск:
```bash
make test-integration ENV=vm-dev
```

## Проверка GitLab
Проверяет namespace `devops`, root secret, ingress, PVC, rollout Deployment/StatefulSet и внешние endpoints `gitlab.mdp`/`registry.mdp`, если доступны Terraform outputs.

Запуск:
```bash
make test-gitlab ENV=vm-dev
```

## Проверка хранения данных
Создаёт временный PVC, записывает данные из одного Pod'а и читает их из другого Pod'а, подтверждая работу default `local-path` storage class.

Запуск:
```bash
make test-storage ENV=vm-dev
```

## Нагрузочное тестирование
Использует `k6` для генерации HTTP-трафика и наблюдения за поведением горизонтального масштабирования.

## Отказовые проверки
Включают сценарий потери worker-узла и контроль состояния control plane.

Неразрушающая проверка control plane:
```bash
make test-resilience ENV=vm-dev
```

Управляемый drain worker-узла выполняется вручную:
```bash
make test-fail-node ENV=vm-dev
```

## Полный регулярный набор
```bash
make test-all ENV=vm-dev
```

`test-all` не включает нагрузочный тест и оставляет worker-drain отдельной ручной проверкой.
