# Модель безопасности

В репозитории реализован базовый контур безопасности, пригодный для демонстрационной, но содержательной платформенной модели.

## Реализованные меры
- разделение пространств имён;
- Role-Based Access Control;
- политика default deny и выборочные сетевые правила;
- Vault как центральный компонент управления секретами с Terraform-описанием auth methods, policies и KV v2;
- Vault Agent Injector для доставки секретов в Pod'ы по Kubernetes ServiceAccount;
- отдельные ServiceAccount для API, gateway и frontend;
- ограничение внешнего доступа через security group и Yandex Network Load Balancer;
- интеграция секрета реестра для загрузки приватных образов;
- GitLab root password и Grafana admin password передаются через переменные окружения/CI variables, а не хранятся в values-файлах.
- GitLab/PostgreSQL secrets не пересоздаются при повторном deploy; ротация включается только явными `ROTATE_*` переменными;
- CI не публикует kubeadm join-команды, а kubeconfig-артефакт ограничен maintainer-доступом и коротким TTL;
- шаблонные CIDR для SSH/API/ingress закрыты на TEST-NET placeholder `203.0.113.10/32` и требуют явной замены перед запуском;
- egress security group вынесен в `allowed_egress_cidrs`, чтобы production-контур мог перейти на controlled NAT/proxy;
- GitLab signup отключён на initial install;
- GitLab Runner controller работает в `devops`, а job pods вынесены в отдельный namespace `ci`;
- GitLab Runner не запускает privileged job pods, имеет resource limits и ограниченный Role только в namespace `ci`;
- Alloy собирает логи через Kubernetes API без hostPath и privileged-доступа к файловой системе узлов.
- прикладные Pod'ы получили baseline hardening: `runAsNonRoot`, `seccompProfile: RuntimeDefault`, запрет privilege escalation, drop capabilities, read-only root filesystem, PDB и topology spread;
- прикладной deployer вынесен в отдельный ServiceAccount `app-deployer`, default ServiceAccount больше не получает deploy-права;
- публичный профиль принимает только `TLS_CLUSTER_ISSUER=letsencrypt-prod`; non-prod ClusterIssuer удаляются deploy-скриптами;
- CDN вынесен в отдельный Terraform edge-слой и по умолчанию выключен, чтобы приватный стенд не публиковался наружу случайно.

## Отложенные меры
Полноценная интеграция с внешним identity provider, например Keycloak, рассматривается только как направление развития и не входит в завершённый объём реализации.

Для production-grade эксплуатации также нужно включить TLS для внутреннего Vault listener, убрать `--kubelet-insecure-tls` после настройки kubelet serving certificates, перевести GitLab PostgreSQL/Redis/Object Storage на managed/external сервисы, проверить cache policy CDN на отсутствие приватных данных и добавить отдельную backup/restore процедуру GitLab.

## Особенности Vault
Первичный `init/unseal` остаётся операционной процедурой, потому что Vault до инициализации не может принять Terraform-конфигурацию через собственный API. После этого Terraform-слой `terraform/vault` настраивает Kubernetes auth, политики и демонстрационные секреты, а bootstrap-материалы сохраняются в `.artifacts/<env>/vault-init.json` с правами `0600`.

## Режим demo-секретов
По умолчанию deployment-скрипты требуют реальные секреты через переменные окружения. Для временного локального стенда можно явно включить `ALLOW_INSECURE_DEMO_SECRETS=true`; такой режим создаёт или использует demo-значения и не должен применяться для stage/prod-like проверки.
