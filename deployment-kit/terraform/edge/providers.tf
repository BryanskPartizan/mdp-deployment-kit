# Edge-слой использует тот же каталог Yandex Cloud, что и основной VM-контур.
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}

# Cloudflare используется для публичного домена, который не делегирован в Yandex Cloud DNS.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
