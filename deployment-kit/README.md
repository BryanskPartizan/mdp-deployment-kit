# Переносимый deployment kit прикладной платформы

Данный репозиторий содержит переносимый deployment kit для воспроизводимого развертывания прикладной платформы в self-hosted Kubernetes-кластере, собираемом с помощью **kubeadm** на виртуальной инфраструктуре.

## Назначение репозитория
Репозиторий реализует послойную модель поставки инфраструктуры и приложений:
1. подготовка инфраструктурных ресурсов и метаданных узлов средствами Terraform;
2. настройка edge-контура доменов, DNS и публичных endpoints;
3. подготовка операционной системы и сборка kubeadm-кластера средствами Ansible;
4. установка базовых платформенных сервисов, необходимых для эксплуатации приложения;
5. развертывание Vault, GitLab и Container Registry;
6. развертывание прикладного контура через Helm charts и параметры окружения;
7. проверка результата smoke-, нагрузочными, интеграционными и отказовыми сценариями.

Эталонная топология репозитория рассчитана на **3 управляющих узла и 2 worker-узла**. При необходимости количество узлов может быть изменено через Terraform-переменные.

## Контуры решения
### Прикладной контур
- API
- frontend
- gateway
- PostgreSQL
- Redis

В каталоге `apps/` лежат минимальные demo-заглушки для `API`, `gateway` и `frontend`: простая форма создаёт сущность, а чтение выполняется по id через маршрут `/entities/:id`.

### Платформенный контур
- ingress-nginx с публикацией через NodePort на worker-узлах
- cert-manager с production Let's Encrypt ClusterIssuer для публичных TLS-сертификатов
- local-path-provisioner для динамического создания локальных PVC
- Vault
- Prometheus + Grafana
- Loki + Alloy
- metrics-server
- blackbox exporter для проверки внутренних и ingress endpoint'ов
- Grafana dashboards и PrometheusRule для кластера, приложений, endpoint'ов и платформенных компонентов
- Terraform edge-слой для Cloudflare DNS only записей, Cloud DNS/Certificate Manager/CDN расширений
- namespaces, RBAC и NetworkPolicy
- резервное копирование PostgreSQL в демонстрационном варианте

### Контур поставки изменений
- pipeline инфраструктуры
- pipeline приложения
- интеграция с GitLab Container Registry

## Верхнеуровневый поток развертывания
```text
Terraform -> generated inventory -> Ansible kubeadm bootstrap -> platform services -> Vault -> GitLab -> application charts -> tests
```

## Подробная инструкция
Подготовка Yandex Cloud до запуска описана в `docs/10-preparation/yandex-cloud-preparation.md`.
Полный порядок запуска, настройки секретов, проверки GitLab, публикации приложений, запуска тестов и очистки стенда описан в `docs/20-runbook/runbook.md`.
Публикация на домен, TLS и CDN описаны в `docs/10-preparation/domain-cdn.md`.

## Быстрый запуск
```bash
make infra-plan ENV=vm-dev
make infra-apply ENV=vm-dev
make edge-apply ENV=vm-dev
make kubeadm-bootstrap ENV=vm-dev
make deploy-platform ENV=vm-dev
make deploy-vault ENV=vm-dev
make vault-init ENV=vm-dev
make vault-configure ENV=vm-dev
make deploy-gitlab ENV=vm-dev
make prepare-gitlab-registry-projects ENV=vm-dev
make bootstrap-gitlab-app-ci ENV=vm-dev
make docker-registry-login ENV=vm-dev
PUSH_IMAGES=true make build-stub-images
make deploy-apps ENV=vm-dev
make test-smoke ENV=vm-dev
make test-network ENV=vm-dev
make test-security ENV=vm-dev
make test-integration ENV=vm-dev
make test-gitlab ENV=vm-dev
```
