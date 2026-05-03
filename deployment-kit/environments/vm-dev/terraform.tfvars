yc_cloud_id      = "b1g5h2eidfj5nvj9m691"
yc_folder_id     = "b1gsetoo8rdt9uhavi9d"
yc_zone          = "ru-central1-a"
cluster_name     = "mdp-k8s-dev"
vm_prefix        = "mdp"
network_cidr     = "10.10.10.0/24"
ssh_public_key_path = "/Users/mdpavlyutin/.ssh/dk-yc-ed25519.pub"
ssh_user = "ubuntu"
node_count_cp    = 3
node_count_worker = 2
# Замените на внешний IP оператора или VPN CIDR. TEST-NET адрес оставлен как безопасный placeholder.
allowed_ssh_cidrs = ["0.0.0.0/0"]
allowed_api_cidrs = ["0.0.0.0/0"]
allowed_ingress_cidrs = ["0.0.0.0/0"]
ingress_http_node_port = 30080
ingress_https_node_port = 30443
