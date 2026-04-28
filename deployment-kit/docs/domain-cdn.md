# Домены, TLS и CDN

Deployment-kit разделяет два режима публикации:

- приватный demo/stage-домен `mdp` с self-signed TLS;
- реальный публичный домен с Cloud DNS, Let's Encrypt/Certificate Manager и опциональным Yandex Cloud CDN.

## Приватный режим mdp

По умолчанию используются hostnames:

```text
app.mdp
gateway.mdp
api.mdp
gitlab.mdp
registry.mdp
minio.mdp
```

`mdp` не является публичным доменом, поэтому стартовый TLS-режим — `test-selfsigned`. Это осознанный дефолт: стенд можно поднять без регистрации домена, DNS delegation и ACME-зависимостей.

После `make infra-apply ENV=vm-dev` выполните:

```bash
make edge-apply ENV=vm-dev
cat .artifacts/vm-dev/hosts-mdp
```

Файл `.artifacts/vm-dev/hosts-mdp` содержит строки вида:

```text
<INGRESS_IP> app.mdp
<INGRESS_IP> gateway.mdp
<INGRESS_IP> gitlab.mdp
<INGRESS_IP> registry.mdp
```

Для доступа из браузера добавьте эти строки в локальный `/etc/hosts` или в корпоративный DNS. В тестах можно использовать `curl -k --resolve`, поэтому системный DNS для CI не обязателен.

Smoke, network, GitLab и load проверки используют `mdp` как fallback. Для публичного домена достаточно экспортировать `APP_DOMAIN=<domain>`, если не нужны точечные overrides.

## Edge Terraform layer

Edge-слой находится в `terraform/edge` и запускается отдельно:

```bash
make edge-plan ENV=vm-dev
make edge-apply ENV=vm-dev
```

Скрипт берёт `ingress_external_ip` и `network_id` из `.artifacts/<env>/terraform-outputs.json`, а настройки — из `environments/<env>/edge.tfvars`.

Дефолтный профиль:

```hcl
domain_name = "mdp"
dns_mode    = "hosts"
cdn_enabled = false
```

В этом режиме Terraform не создаёт DNS/CDN-ресурсы, а только сохраняет outputs и hosts-файл.

## Публичный домен

Для реального домена, например `example.com`, поменяйте `environments/vm-dev/edge.tfvars`:

```hcl
domain_name     = "example.com"
dns_mode        = "public"
create_dns_zone = true
cdn_enabled     = false
```

После `make edge-apply` в Yandex Cloud появится public DNS zone и A-записи на ingress NLB для `app`, `gateway`, `api`, `gitlab`, `registry`, `minio`.

Если zone создаётся в Yandex Cloud, у регистратора домена нужно делегировать NS-записи на NS-серверы созданной Cloud DNS zone. Без delegation публичные клиенты не смогут найти записи.

Для Kubernetes ingress укажите домен и TLS issuer в `.env`:

```bash
APP_DOMAIN=example.com
TLS_CLUSTER_ISSUER=letsencrypt-staging
LETSENCRYPT_EMAIL=admin@example.com
```

Сначала проверьте staging issuer, затем переключайтесь на production:

```bash
TLS_CLUSTER_ISSUER=letsencrypt-prod
```

`letsencrypt-*` работает только если публичные DNS-записи уже указывают на ingress NLB и порт `80` доступен извне для HTTP-01 challenge.

## CDN для frontend

CDN нужен в первую очередь для статического frontend. API, GitLab и container registry лучше публиковать напрямую через ingress NLB: у них другие требования к методам, авторизации, streaming и cache-control.

Пример `edge.tfvars` для CDN:

```hcl
domain_name                    = "example.com"
dns_mode                       = "public"
create_dns_zone                = true
cdn_enabled                    = true
cdn_hostname                   = "cdn.example.com"
cdn_origin_hostname            = "origin.example.com"
cdn_origin_protocol            = "http"
cdn_origin_host_header         = "app.example.com"
cdn_create_managed_certificate = true
```

Terraform создаст:

- A-запись `origin.example.com -> <INGRESS_IP>`;
- origin group для ingress;
- CDN resource `cdn.example.com`;
- managed certificate в Certificate Manager через DNS CNAME challenge;
- CNAME `cdn.example.com -> <provider_cname>`.

Для `mdp` CDN не используется: CDN требует публичный hostname, а браузерный TLS на edge должен иметь сертификат для публичного домена.

## Практические ограничения

- Не используйте CDN на apex-домене без DNS-провайдера с ALIAS/ANAME. Надёжнее выделять поддомены: `app.example.com`, `cdn.example.com`, `origin.example.com`.
- Для публичного стенда можно открыть `allowed_ingress_cidrs = ["0.0.0.0/0"]`, но `allowed_ssh_cidrs` и `allowed_api_cidrs` должны оставаться ограниченными вашим IP/VPN.
- Self-signed режим подходит для demo и приватного `mdp`, но не для публичных пользователей.
- Если CDN ходит к origin по `https`, сертификат origin тоже должен быть валидным. Поэтому дефолт CDN origin protocol — `http`, а TLS завершается на CDN edge.

## Полезные ссылки

- Yandex Cloud CDN resource: https://yandex.cloud/en/docs/terraform/resources/cdn_resource
- Yandex Cloud CDN origin group: https://yandex.cloud/en/docs/terraform/resources/cdn_origin_group
- Certificate Manager: https://yandex.cloud/en/docs/certificate-manager
- Cloud DNS records: https://yandex.cloud/en/docs/dns/concepts/resource-record
