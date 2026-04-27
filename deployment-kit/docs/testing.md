# Модель тестирования

Deployment kit включает несколько категорий проверок, разделённых по риску и назначению.

## Smoke-тестирование
Подтверждает доступность endpoint, публикацию через ingress и работу базовых health-check маршрутов.

Запуск:
```bash
make test-smoke ENV=vm-dev
```

## Проверка сетевой связанности
Проверяет разрешённые маршруты между ingress, gateway, API, PostgreSQL и Redis, а также внешние точки входа Yandex Network Load Balancer. Для проверки используются временные диагностические Pod'ы с теми же labels, которые участвуют в `NetworkPolicy`.

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
Проверяет rollout платформенных компонентов, StatefulSet/Deployment прикладного контура, наличие Endpoints, HTTP health endpoints и полный путь Vault Agent Injector от Kubernetes ServiceAccount до injected secret file.

Запуск:
```bash
make test-integration ENV=vm-dev
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
