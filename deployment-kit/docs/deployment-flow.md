# Логика развертывания

Процесс развертывания намеренно разделён на отдельные стадии, каждая из которых может быть описана, воспроизведена и проверена независимо.

## Стадия 1. Подготовка инфраструктуры
Terraform создаёт сеть, виртуальные машины, группы безопасности, target groups и два сетевых балансировщика Yandex Cloud. По завершении стадии формируется Ansible inventory в файле `ansible/inventory/generated/hosts.yml`; kubeadm `controlPlaneEndpoint` указывает на внешний IP API-балансировщика.

## Стадия 2. Сборка kubeadm-кластера
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

## Стадия 3. Развертывание и настройка Vault
Terraform-слой `terraform/platform` устанавливает Vault Helm chart в HA-режиме с Raft-хранилищем. После операционного `init/unseal` Terraform-слой `terraform/vault` настраивает Kubernetes auth, политики доступа и KV v2 secrets engine.

## Стадия 4. Развертывание платформенных сервисов
На этой стадии устанавливаются namespaces, ingress-контроллер, cert-manager, контур наблюдаемости и metrics-server.

## Стадия 5. Развертывание GitLab
GitLab разворачивается как devops-компонент в namespace `devops`. Chart использует внешний ingress-nginx deployment-kit, cert-manager ClusterIssuer `test-selfsigned` и storage class `local-path`. Root password передаётся через Kubernetes Secret `gitlab-root-password`, создаваемый из защищённой переменной `GITLAB_ROOT_PASSWORD`. GitLab Runner включён в тот же Helm release, чтобы установленный GitLab мог исполнять pipeline jobs.

## Стадия 6. Развертывание прикладного контура
На прикладной стадии развертываются PostgreSQL, Redis, API, gateway и frontend, после чего применяются манифесты безопасности и резервного копирования.

## Стадия 7. Верификация
Smoke-тесты, нагрузочные проверки и отказовые сценарии подтверждают доступность сервисов, работу масштабирования и реакцию системы на потерю worker-узла.

## Стадия 8. Удаление стенда
Для пересборки Kubernetes на тех же VM используется `make kubeadm-reset ENV=<env>` с явным подтверждением `CONFIRM_RESET=<env>`. Эта операция очищает kubeadm, etcd, kubelet, CNI и локальные bootstrap-артефакты, но не удаляет VM и сетевые ресурсы.

Инфраструктура удаляется через `make infra-destroy ENV=<env>` с явным подтверждением `CONFIRM_DESTROY=<env>`, чтобы исключить случайное уничтожение окружения.
