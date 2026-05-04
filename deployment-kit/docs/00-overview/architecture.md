# Архитектура

Deployment kit организован по семи основным слоям реализации:

1. **Слой подготовки инфраструктуры** на базе Terraform, отвечающий за создание виртуальных машин, сети, групп безопасности, HA endpoint Kubernetes API и балансировщика входящего HTTP/HTTPS-трафика.
2. **Слой сборки кластера** на базе Ansible и kubeadm, отвечающий за формирование self-hosted Kubernetes-кластера из 3 control-plane и 2 worker-узлов.
3. **Слой Vault**, в котором Terraform устанавливает Vault в Kubernetes и настраивает Kubernetes auth, политики и KV-хранилище секретов.
4. **Слой платформенных сервисов**, в котором устанавливаются ingress, управление сертификатами, метрики и журналирование.
5. **Edge-слой**, в котором Terraform управляет Cloudflare DNS only записями, а также расширениями Cloud DNS, Certificate Manager и CDN.
6. **DevOps-контур**, в котором разворачивается GitLab и GitLab Container Registry для хранения исходного кода, pipeline и образов.
7. **Слой прикладного контура**, в котором через Helm разворачиваются PostgreSQL, Redis, API, gateway и frontend.

Такая структура намеренно согласована с логикой практической главы ВКР и с последовательностью автоматизированного развертывания решения.

## Внешние точки входа
Для self-hosted kubeadm-кластера используется два Yandex Network Load Balancer:
- балансировщик Kubernetes API принимает `6443` и направляет трафик на все control-plane узлы;
- балансировщик ingress принимает `80/443` и направляет трафик на NodePort `30080/30443` worker-узлов.

Такой вариант сохраняет переносимость Kubernetes-слоя и при этом даёт рабочую HA-точку входа для пользователей, CI и администраторов.

## Домены и CDN
Стартовый домен стенда — публичный `pkhco.ru`. TLS выпускается только через production Let's Encrypt ClusterIssuer `letsencrypt-prod`. Отдельный `terraform/edge` создаёт DNS only записи на ingress IP; CDN остаётся опциональным расширением для публичных hostname.

## DevOps-контур
GitLab устанавливается в namespace `devops` через официальный Helm chart вместе с GitLab Runner и Container Registry. GitLab Runner controller остаётся в `devops`, а CI job pods запускаются в отдельном namespace `ci`, чтобы RBAC runner'а не давал широкие права внутри namespace GitLab. В демонстрационном профиле используются bundled PostgreSQL, Redis и MinIO chart dependencies, потому что цель deployment-kit — поднять самодостаточный стенд. Для промышленной эксплуатации этот слой должен быть переведён на внешние managed PostgreSQL/Redis/Object Storage.
