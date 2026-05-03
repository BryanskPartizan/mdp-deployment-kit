# Домены, TLS и CDN

Deployment-kit разделяет два режима публикации:

- приватный demo/stage-домен `mdp` с self-signed TLS;
- реальный публичный домен с Cloud DNS, Let's Encrypt/Certificate Manager и опциональным Yandex Cloud CDN.

## Приватный режим mdp

Приватный режим включается явно:

```bash
export APP_DOMAIN=mdp
export TLS_CLUSTER_ISSUER=test-selfsigned
```

`mdp` не является публичным доменом, поэтому стартовый TLS-режим — `test-selfsigned`. Это осознанный дефолт: стенд можно поднять без регистрации домена, DNS delegation и ACME-зависимостей.

После `make infra-apply ENV=vm-dev` выполните:

```bash
make edge-apply ENV=vm-dev
cat .artifacts/vm-dev/hosts-file
```

Файл `.artifacts/vm-dev/hosts-file` содержит строки вида:

```text
<INGRESS_IP> app.mdp
<INGRESS_IP> gateway.mdp
<INGRESS_IP> gitlab.mdp
<INGRESS_IP> registry.mdp
```

Для удобства также создаётся доменный alias, например `.artifacts/vm-dev/hosts-mdp`.

Для доступа из браузера добавьте эти строки в локальный `/etc/hosts` или в корпоративный DNS. В тестах можно использовать `curl -k --resolve`, поэтому системный DNS для CI не обязателен.

Smoke, network, GitLab и load проверки используют публичный `pkhco.ru` как текущий профиль. Для приватного fallback задайте `APP_DOMAIN=mdp` и точечные overrides при необходимости.

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

После `make edge-apply` в выбранном DNS-провайдере появятся public A-записи на ingress NLB для `app`, `gateway`, `api`, `gitlab`, `registry`, `minio` и дополнительных entrypoints.

Если zone создаётся в Yandex Cloud, у регистратора домена нужно делегировать NS-записи на NS-серверы созданной Cloud DNS zone. Без delegation публичные клиенты не смогут найти записи.

Если домен управляется в Cloudflare, используйте DNS only записи:

```hcl
domain_name        = "pkhco.ru"
dns_provider       = "cloudflare"
dns_mode           = "public"
cloudflare_proxied = false
create_dns_zone    = false
cdn_enabled        = false

extra_ingress_hostnames = {
  grafana   = "grafana.pkhco.ru"
  kas       = "kas.pkhco.ru"
  k8s_admin = "k8s-admin.pkhco.ru"
  vault     = "vault.pkhco.ru"
}
```

Перед `make edge-apply` задайте Cloudflare credentials:

```bash
export TF_VAR_cloudflare_zone_id=<cloudflare-zone-id>
export TF_VAR_cloudflare_api_token=<cloudflare-dns-token>
```

Cloudflare proxy должен быть выключен (`cloudflare_proxied=false`): GitLab, Registry, Vault и Headlamp публикуются напрямую через ingress NLB.

Для `k8s-admin.<domain>` обязательно включайте basic auth:

```bash
export K8S_ADMIN_ENABLED=true
export K8S_ADMIN_BASIC_AUTH_HTPASSWD="$(htpasswd -nbB admin '<strong-password>')"
```

Для Kubernetes ingress укажите домен и TLS issuer в `.env`:

```bash
APP_DOMAIN=example.com
TLS_CLUSTER_ISSUER=letsencrypt-prod
LETSENCRYPT_EMAIL=admin@example.com
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

Если первый apply выполняется до полной DNS delegation, managed certificate может долго ждать validation. В этом случае временно задайте:

```hcl
cdn_wait_managed_certificate_validation = false
```

Затем проверьте NS/CNAME challenge и повторите `make edge-apply`.

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
