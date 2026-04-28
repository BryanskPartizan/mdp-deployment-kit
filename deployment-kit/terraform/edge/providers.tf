# Edge-слой использует тот же каталог Yandex Cloud, что и основной VM-контур.
provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}
