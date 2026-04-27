# Модуль явно использует провайдер Yandex Cloud, чтобы Terraform не искал hashicorp/yandex.
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

