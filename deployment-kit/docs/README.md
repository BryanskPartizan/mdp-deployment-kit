# Документация deployment-kit

Данный раздел является навигационной картой документации. Документы сгруппированы по жизненному циклу deployment-kit: от архитектуры и подготовки облака до эксплуатации, тестирования и отчёта по практическому запуску.

## Структура документации

```text
docs/
  README.md                         # навигация по документации
  00-overview/                      # архитектура, состав решения, версии и окружения
  10-preparation/                   # подготовка Yandex Cloud, DNS, TLS и CDN
  20-runbook/                       # пошаговый запуск, kubeadm, backup/restore
  30-operations/                    # наблюдаемость, безопасность и тестирование
  40-audit/                         # аудит готовности и служебные материалы
```

## Что читать в первую очередь

| Задача | Документ |
| --- | --- |
| Понять назначение проекта | [Обзор](00-overview/overview.md) |
| Понять архитектуру решения | [Архитектура](00-overview/architecture.md) |
| Подготовить Yandex Cloud | [Подготовка Yandex Cloud](10-preparation/yandex-cloud-preparation.md) |
| Настроить домен и TLS | [Домены, TLS и CDN](10-preparation/domain-cdn.md) |
| Запустить стенд с нуля | [Runbook запуска и тестирования](20-runbook/runbook.md) |
| Понять kubeadm bootstrap | [Модель kubeadm-кластера](20-runbook/kubeadm-cluster.md) |
| Проверить мониторинг | [Модель наблюдаемости](30-operations/observability.md) |
| Проверить безопасность | [Модель безопасности](30-operations/security-model.md) |
| Запустить тесты | [Модель тестирования](30-operations/testing.md) |
| Зафиксировать версии | [Версии компонентов](00-overview/versions.md) |
| Оценить готовность | [Аудит готовности](40-audit/readiness-audit.md) |

## Общая схема решения

```mermaid
flowchart LR
  operator[Инженер] --> yc[Yandex Cloud]
  operator --> gitlab[GitLab]
  yc --> tf[Terraform]
  tf --> vm[VM: 3 control-plane + 2 worker]
  vm --> ansible[Ansible + kubeadm]
  ansible --> k8s[Kubernetes HA]
  k8s --> platform[Platform: ingress, cert-manager, monitoring, logs]
  platform --> vault[Vault HA]
  platform --> devops[GitLab + Registry + Runner]
  devops --> images[Container images]
  images --> apps[API + Gateway + Frontend]
  apps --> data[(PostgreSQL + Redis)]
  platform --> tests[Smoke / Network / Security / Integration / Load]
```

## Поток запуска

```mermaid
sequenceDiagram
  participant YC as Yandex Cloud
  participant TF as Terraform
  participant AN as Ansible
  participant K8S as Kubernetes
  participant PL as Platform
  participant VA as Vault
  participant GL as GitLab
  participant APP as App contour
  participant T as Tests

  YC->>TF: folder, service account, quotas, DNS credentials
  TF->>YC: VM, network, security group, NLB
  TF->>AN: generated inventory
  AN->>K8S: kubeadm HA bootstrap
  K8S->>PL: ingress-nginx, cert-manager, monitoring, logs
  PL->>VA: Vault Helm release and ingress TLS
  VA->>VA: init, unseal, policies, Kubernetes auth
  PL->>GL: GitLab, Registry, Runner
  GL->>APP: build and push images
  APP->>K8S: Helm deploy API, Gateway, Frontend, PostgreSQL, Redis
  T->>K8S: verification suites
```

## Диаграммы

Актуальные диаграммы расположены в [../diagrams](../diagrams). Для GitHub и Markdown-ориентированного просмотра используются Mermaid-файлы `*.mmd`; для вставки в ВКР через PlantUML сохранены `*.puml`.

## Отчёт о практическом запуске

Нормализованный отчёт по фактическому запуску и тестированию находится в [../../execution-log](../../execution-log) на уровне корня репозитория. Исходный файл `final_log` используется только как локальный сырой журнал и не предназначен для коммита.
