# Переносимый deployment kit прикладной платформы

Данный репозиторий содержит переносимый deployment kit для воспроизводимого развертывания прикладной платформы в self-hosted Kubernetes-кластере, собираемом с помощью **kubeadm** на виртуальной инфраструктуре.

## Назначение репозитория
Репозиторий реализует послойную модель поставки инфраструктуры и приложений:
1. подготовка инфраструктурных ресурсов и метаданных узлов средствами Terraform;
2. подготовка операционной системы и сборка kubeadm-кластера средствами Ansible;
3. установка базовых платформенных сервисов, необходимых для эксплуатации приложения;
4. развертывание прикладного контура через Helm charts и параметры окружения;
5. настройка edge-контура доменов/DNS/CDN;
6. проверка результата smoke-, нагрузочными и отказовыми сценариями.

Эталонная топология репозитория рассчитана на **3 управляющих узла и 2 worker-узла**. При необходимости количество узлов может быть изменено через Terraform-переменные.

## Контуры решения
### Прикладной контур
- API
- frontend
- gateway
- PostgreSQL
- Redis

### Платформенный контур
- ingress-nginx с публикацией через NodePort на worker-узлах
- cert-manager с локальным центром сертификации для демонстрационных TLS-сертификатов
- local-path-provisioner для динамического создания локальных PVC
- Vault
- Prometheus + Grafana
- Loki + Alloy
- metrics-server
- blackbox exporter для проверки внутренних и ingress endpoint'ов
- Grafana dashboards и PrometheusRule для кластера, приложений, endpoint'ов и платформенных компонентов
- Terraform edge-слой для приватного `mdp`, Cloud DNS, Certificate Manager и CDN
- namespaces, RBAC и NetworkPolicy
- резервное копирование PostgreSQL в демонстрационном варианте

### Контур поставки изменений
- pipeline инфраструктуры
- pipeline приложения
- интеграция с GitLab Container Registry

## Верхнеуровневый поток развертывания
```text
Terraform -> generated inventory -> Ansible kubeadm bootstrap -> Vault -> platform services -> GitLab -> application charts -> tests
```

## Подробная инструкция
Подготовка Yandex Cloud до запуска описана в `docs/yandex-cloud-preparation.md`.
Полный порядок запуска, настройки секретов, проверки GitLab, публикации приложений, запуска тестов и очистки стенда описан в `docs/runbook.md`.
Публикация на домен, TLS и CDN описаны в `docs/domain-cdn.md`.

## Быстрый запуск
```bash
make infra-plan ENV=vm-dev
make infra-apply ENV=vm-dev
make edge-apply ENV=vm-dev
make kubeadm-bootstrap ENV=vm-dev
make deploy-vault ENV=vm-dev
make vault-init ENV=vm-dev
make vault-configure ENV=vm-dev
make deploy-platform ENV=vm-dev
make deploy-gitlab ENV=vm-dev
make deploy-apps ENV=vm-dev
make test-smoke ENV=vm-dev
make test-network ENV=vm-dev
make test-security ENV=vm-dev
make test-integration ENV=vm-dev
make test-gitlab ENV=vm-dev
```

## Примечания по Yandex Cloud
- До запуска `make infra-plan` выполните подготовку из `docs/yandex-cloud-preparation.md`.
- Заполните `yc_cloud_id`, `yc_folder_id` и `ssh_public_key_path` в файлах `environments/*/terraform.tfvars`.
- Перед запуском Terraform экспортируйте `TF_VAR_yc_token` либо передайте `yc_token` через tfvars/CI-переменные.
- Kubernetes API публикуется через Yandex Network Load Balancer на порту `6443`; этот адрес используется как kubeadm `controlPlaneEndpoint`.
- Ingress-контроллер публикуется через NodePort `30080/30443`, а внешний HTTP/HTTPS-трафик приходит через отдельный Yandex Network Load Balancer `80/443 -> 30080/30443`.
- Дефолтный приватный домен стенда — `mdp`: `app.mdp`, `gateway.mdp`, `gitlab.mdp`, `registry.mdp`. Для него используется self-signed TLS через cert-manager issuer `test-selfsigned`.
- Edge-слой `terraform/edge` может только сгенерировать hosts-записи для `mdp` либо управлять Cloud DNS, Certificate Manager и CDN для реального публичного домена.
- Класс хранения по умолчанию — `local-path`, что позволяет динамически создавать PVC для PostgreSQL, Redis, Prometheus и Loki на локальном хранилище узлов.
- Vault устанавливается Terraform-слоем `terraform/platform`, а auth methods, policies и demo-секреты описаны в `terraform/vault`.
- GitLab разворачивается как devops-компонент платформы через официальный chart `gitlab/gitlab` и публикуется через тот же ingress NLB на `gitlab.mdp` и `registry.mdp`.
- Секреты передаются через переменные окружения/CI variables. Для локального стенда используйте `.env.example` как шаблон, но не коммитьте `.env`.

## Дополнительные замечания
- Структура репозитория подготовлена так, чтобы её можно было непосредственно описывать в практической главе ВКР.
- Каталог AWS отражает направление дальнейшего расширения. Основная полноценно реализованная цель репозитория — self-hosted кластер на VM-инфраструктуре Yandex Cloud.
- Join-токены и certificate-key формируются в процессе bootstrap и сохраняются локально в каталоге `.artifacts/` для следующих стадий развертывания.
- Зафиксированные версии Terraform providers и Helm charts перечислены в `docs/versions.md`.
- Подробный runbook запуска и тестирования находится в `docs/runbook.md`.
- Текущий аудит готовности и остаточные production gaps описаны в `docs/readiness-audit.md`.
- Для пересборки Kubernetes на существующих VM используйте явное подтверждение: `CONFIRM_RESET=vm-dev make kubeadm-reset ENV=vm-dev`.
- Для удаления инфраструктуры используйте явное подтверждение: `CONFIRM_DESTROY=vm-dev make infra-destroy ENV=vm-dev`.
