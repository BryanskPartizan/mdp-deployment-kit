yc_cloud_id  = "b1g5h2eidfj5nvj9m691"
yc_folder_id = "b1gsetoo8rdt9uhavi9d"
yc_zone      = "ru-central1-a"

cluster_name = "mdp-k8s-dev"

# Публичный домен управляется в Cloudflare. Включаем DNS only записи на внешний IP ingress NLB.
domain_name        = "pkhco.ru"
dns_provider       = "cloudflare"
dns_mode           = "public"
cloudflare_proxied = false
create_dns_zone    = false
cdn_enabled        = false

# Дополнительные публичные entrypoints платформы.
extra_ingress_hostnames = {
  grafana   = "grafana.pkhco.ru"
  kas       = "kas.pkhco.ru"
  k8s_admin = "k8s-admin.pkhco.ru"
  vault     = "vault.pkhco.ru"
}
