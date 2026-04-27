# Фиксируем минимальные версии Terraform и провайдера для воспроизводимого запуска.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.201.0"
    }
  }
}
