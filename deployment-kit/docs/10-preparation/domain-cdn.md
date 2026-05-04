# Домены, TLS и CDN

Deployment-kit поддерживает публичный профиль публикации. Дефолтный домен стенда — `pkhco.ru`, DNS управляется через Cloudflare в режиме DNS only, TLS выпускается cert-manager через production Let's Encrypt ClusterIssuer `letsencrypt-prod`.

Приватные домены и non-prod issuers больше не являются поддерживаемым deploy-профилем. Скрипты `deploy-platform`, `deploy-gitlab`, `deploy-vault` и `deploy-apps` завершаются ошибкой, если `APP_DOMAIN` не является публичным доменом или `TLS_CLUSTER_ISSUER` отличается от `letsencrypt-prod`.

## Edge Terraform layer

Edge-слой находится в `terraform/edge` и запускается отдельно:

```bash
make edge-plan ENV=vm-dev
make edge-apply ENV=vm-dev
```

Скрипт берёт `ingress_external_ip` и `network_id` из `.artifacts/<env>/terraform-outputs.json`, а настройки — из `environments/<env>/edge.tfvars`.

Дефолтный публичный профиль:

```hcl
domain_name        = "pkhco.ru"
dns_provider       = "cloudflare"
dns_mode           = "public"
cloudflare_proxied = false
create_dns_zone    = false
cdn_enabled        = false
```

Cloudflare-записи должны оставаться **DNS only**. Proxy/CDN Cloudflare для GitLab Registry и Kubernetes ingress на этом этапе не используется, чтобы не ломать Docker Registry auth, WebSocket/KAS и ACME HTTP-01 проверки.

Перед запуском задайте credentials Cloudflare:

```bash
export TF_VAR_cloudflare_zone_id=<cloudflare-zone-id>
export TF_VAR_cloudflare_api_token=<cloudflare-dns-token>
make edge-apply ENV=vm-dev
```

Terraform создаёт A-записи на ingress NLB для:

```text
app.pkhco.ru
gateway.pkhco.ru
api.pkhco.ru
gitlab.pkhco.ru
registry.pkhco.ru
kas.pkhco.ru
grafana.pkhco.ru
k8s-admin.pkhco.ru
vault.pkhco.ru
minio.pkhco.ru
```

## TLS

Платформенный слой устанавливает cert-manager и создаёт только production ClusterIssuer:

```text
letsencrypt-prod -> https://acme-v02.api.letsencrypt.org/directory
```

Перед `deploy-platform` публичные DNS-записи уже должны указывать на ingress IP. Иначе HTTP-01 challenge не пройдёт, и cert-manager оставит сертификаты в состоянии `Pending`.

Минимальные переменные:

```bash
export APP_DOMAIN=pkhco.ru
export TLS_CLUSTER_ISSUER=letsencrypt-prod
export LETSENCRYPT_EMAIL=<email>
```

Проверки после деплоя:

```bash
kubectl get clusterissuer
kubectl -n observability get certificate grafana-tls
kubectl -n devops get certificate gitlab-webservice-tls gitlab-registry-tls
kubectl -n app get certificate gateway-tls frontend-tls
```

Сертификаты должны быть `READY=True`, а issuer в браузере или `openssl s_client` должен быть Let's Encrypt.

## CDN

CDN остаётся опциональным расширением и должен включаться только для статических публичных ресурсов, где нет приватных cookies, API-токенов и пользовательских данных.

Практические ограничения:

- не используйте CDN на apex-домене без DNS-провайдера с ALIAS/ANAME;
- лучше выделять отдельные hostnames: `cdn.example.com`, `static.example.com`;
- GitLab, Registry, Vault, Grafana и k8s-admin не нужно помещать за CDN;
- если CDN ходит к origin по HTTPS, origin-сертификат тоже должен быть валидным production Let's Encrypt.

## Диагностика

Проверить DNS:

```bash
dig +short app.pkhco.ru
dig +short registry.pkhco.ru
```

Проверить TLS:

```bash
openssl s_client -connect app.pkhco.ru:443 -servername app.pkhco.ru </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Если виден `Kubernetes Ingress Controller Fake Certificate`, значит ingress ещё не получил валидный secret от cert-manager. Смотрите:

```bash
kubectl -n app describe certificate frontend-tls
kubectl -n app get order,challenge
kubectl -n cert-manager logs deploy/cert-manager
```
