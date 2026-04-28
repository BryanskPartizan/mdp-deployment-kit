yc_cloud_id  = "REPLACE_WITH_YC_CLOUD_ID"
yc_folder_id = "REPLACE_WITH_YC_FOLDER_ID"
yc_zone      = "ru-central1-a"

cluster_name = "demo-k8s-dev"

# Приватный стартовый домен стенда. Для него используется self-signed TLS и локальные hosts-записи.
domain_name = "mdp"
dns_mode    = "hosts"

# Для реального публичного домена поменяйте domain_name, включите dns_mode="public",
# create_dns_zone=true и при необходимости cdn_enabled=true.
create_dns_zone = false
cdn_enabled     = false
