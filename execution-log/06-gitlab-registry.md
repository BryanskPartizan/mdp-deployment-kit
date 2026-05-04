# Этап 6. GitLab и Container Registry

## Цель этапа

Развернуть GitLab в Kubernetes, проверить его готовность, создать проекты для прикладных сервисов
и подготовить Container Registry для публикации образов.

## Развертывание GitLab

```bash
make deploy-gitlab ENV=vm-dev
```

Значимый вывод:

```text
namespace/devops configured
namespace/ci configured
secret/gitlab-root-password created
Release "gitlab" does not exist. Installing it now.
NAME: gitlab
NAMESPACE: devops
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
GitLab root password хранится в Kubernetes secret devops/gitlab-root-password.
```

## Проверка GitLab

```bash
make test-gitlab ENV=vm-dev
```

Значимый вывод:

```text
== Проверки GitLab ==
  • GitLab components and endpoints                           OK (11s)
Итог: 1/1 OK.
```

## Подготовка проектов registry

```bash
make prepare-gitlab-registry-projects ENV=vm-dev
```

Значимый вывод:

```text
Подготовка GitLab registry projects через devops/gitlab-toolbox-ff5fc54f-rhmff.
Создана GitLab group platform
Создан GitLab project platform/api
Создан GitLab project platform/gateway
Создан GitLab project platform/frontend
```

## Вход в Container Registry

```bash
make docker-registry-login ENV=vm-dev
```

Значимый вывод:

```text
Docker trust не настраивается: registry должен иметь production Let's Encrypt сертификат.
Docker login в registry.pkhco.ru пользователем root.
Login Succeeded
```

## Особенности этапа

GitLab Helm chart выводит upstream-предупреждения о встроенных PostgreSQL, Redis и MinIO. Для
стенда ВКР это зафиксировано как допустимое ограничение dev-среды. Для production-эксплуатации
потребуется вынести эти сервисы во внешние управляемые компоненты или отдельные отказоустойчивые
контуры.

## Результат этапа

<span style="color:#16833a"><strong>Успешно.</strong></span> GitLab доступен, проверка endpoints
прошла, проекты `platform/api`, `platform/gateway`, `platform/frontend` созданы, Docker login в
`registry.pkhco.ru` завершен успешно.

