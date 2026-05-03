# Логика развертывания

Процесс развертывания намеренно разделён на отдельные стадии, каждая из которых может быть описана, воспроизведена и проверена независимо.

Практический пошаговый порядок запуска с командами, переменными окружения и контрольными проверками описан в `docs/runbook.md`.

## Стадия 1. Подготовка инфраструктуры
Terraform создаёт сеть, виртуальные машины, группы безопасности, target groups и два сетевых балансировщика Yandex Cloud. По завершении стадии формируется Ansible inventory в файле `ansible/inventory/generated/hosts.yml`; kubeadm `controlPlaneEndpoint` указывает на внешний IP API-балансировщика.

## Стадия 2. Edge/DNS
Terraform-слой `terraform/edge` получает ingress IP из output основной инфраструктуры. В дефолтном режиме он создаёт hosts-файл для приватного домена `mdp`; для публичного домена может управлять Cloud DNS, Certificate Manager и Yandex Cloud CDN.

## Стадия 3. Сборка kubeadm-кластера
Ansible выполняет:
- подготовку операционной системы;
- установку контейнерного runtime;
- установку пакетов Kubernetes;
- подготовку параметров ядра;
- preflight-проверки inventory, ОС, containerd, swap, sysctl и занятых портов;
- `kubeadm init` на первом control-plane узле;
- проверку доступности Kubernetes API через HA endpoint;
- `kubeadm join --control-plane` на остальных управляющих узлах;
- `kubeadm join` на worker-узлах;
- установку закреплённой версии CNI;
- экспорт kubeconfig и завершающие post-bootstrap проверки CoreDNS, kube-proxy, Ready nodes и etcd health.

## Стадия 4. Развертывание и настройка Vault
Terraform-слой `terraform/platform` устанавливает Vault Helm chart в HA-режиме с Raft-хранилищем. После операционного `init/unseal` Terraform-слой `terraform/vault` настраивает Kubernetes auth, политики доступа и KV v2 secrets engine.

## Стадия 5. Развертывание платформенных сервисов
На этой стадии устанавливаются namespaces, ingress-контроллер, cert-manager, metrics-server, контур наблюдаемости, blackbox exporter, Grafana dashboards и Prometheus alert rules.

## Стадия 6. Развертывание GitLab
GitLab разворачивается как devops-компонент в namespace `devops`. Chart использует внешний ingress-nginx deployment-kit, cert-manager ClusterIssuer `letsencrypt-prod` для публичного профиля и storage class `local-path`. Root password передаётся через Kubernetes Secret `gitlab-root-password`, создаваемый из защищённой переменной `GITLAB_ROOT_PASSWORD`; при повторном deploy secret не пересоздаётся без явного `ROTATE_GITLAB_ROOT_PASSWORD=true`. GitLab Runner controller включён в тот же Helm release, а CI job pods вынесены в namespace `ci`, чтобы runner RBAC не имел широких прав внутри namespace GitLab.

## Стадия 7. Развертывание прикладного контура
На прикладной стадии развертываются PostgreSQL, Redis, API, gateway и frontend, после чего применяются манифесты безопасности и резервного копирования. PostgreSQL secret создаётся только при первом запуске, а приложения получают явные egress NetworkPolicy, baseline Pod security context, PDB и topology spread.

## Стадия 8. Верификация
Smoke-тесты, нагрузочные проверки и отказовые сценарии подтверждают доступность сервисов, работу масштабирования и реакцию системы на потерю worker-узла.

## Стадия 9. Удаление стенда
Для пересборки Kubernetes на тех же VM используется `make kubeadm-reset ENV=<env>` с явным подтверждением `CONFIRM_RESET=<env>`. Эта операция очищает kubeadm, etcd, kubelet, CNI и локальные bootstrap-артефакты, но не удаляет VM и сетевые ресурсы.

Инфраструктура удаляется через `make infra-destroy ENV=<env>` с явным подтверждением `CONFIRM_DESTROY=<env>`, чтобы исключить случайное уничтожение окружения.
