# Переносимый deployment kit прикладной платформы

Данный репозиторий содержит переносимый deployment kit для воспроизводимого развертывания прикладной платформы в self-hosted Kubernetes-кластере, собираемом с помощью **kubeadm** на виртуальной инфраструктуре.

## Назначение репозитория
Репозиторий реализует послойную модель поставки инфраструктуры и приложений:
1. подготовка инфраструктурных ресурсов и метаданных узлов средствами Terraform;
2. подготовка операционной системы и сборка kubeadm-кластера средствами Ansible;
3. установка базовых платформенных сервисов, необходимых для эксплуатации приложения;
4. развертывание прикладного контура через Helm charts и параметры окружения;
5. проверка результата smoke-, нагрузочными и отказовыми сценариями.

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
- Loki + Promtail
- metrics-server
- namespaces, RBAC и NetworkPolicy
- резервное копирование PostgreSQL в демонстрационном варианте

### Контур поставки изменений
- pipeline инфраструктуры
- pipeline приложения
- интеграция с GitLab Container Registry

## Верхнеуровневый поток развертывания
```text
Terraform -> generated inventory -> Ansible kubeadm bootstrap -> platform services -> application charts -> tests
```

## Быстрый запуск
```bash
make infra-plan ENV=vm-dev
make infra-apply ENV=vm-dev
make kubeadm-bootstrap ENV=vm-dev
make deploy-platform ENV=vm-dev
make deploy-apps ENV=vm-dev
make test-smoke ENV=vm-dev
```

## Примечания по Yandex Cloud
- Заполните `yc_cloud_id`, `yc_folder_id` и `ssh_public_key_path` в файлах `environments/*/terraform.tfvars`.
- Перед запуском Terraform экспортируйте `TF_VAR_yc_token` либо передайте `yc_token` через tfvars/CI-переменные.
- Ingress-контроллер публикуется через NodePort `30080/30443`. В варианте self-hosted на виртуальных машинах запросы должны направляться на внешний IP worker-узла либо на внешний балансировщик перед пулом worker-узлов.
- Класс хранения по умолчанию — `local-path`, что позволяет динамически создавать PVC для PostgreSQL, Redis, Prometheus и Loki на локальном хранилище узлов.

## Дополнительные замечания
- Структура репозитория подготовлена так, чтобы её можно было непосредственно описывать в практической главе ВКР.
- Каталог AWS отражает направление дальнейшего расширения. Основная полноценно реализованная цель репозитория — self-hosted кластер на VM-инфраструктуре Yandex Cloud.
- Join-токены и certificate-key формируются в процессе bootstrap и сохраняются локально в каталоге `.artifacts/` для следующих стадий развертывания.
