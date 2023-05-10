
# В отдельный файл variables.tf

variable "zone_a" {
  description = "Use specific availability zone"
  type        = string
  default     = "ru-central1-a"
}

variable "zone_b" {
  description = "Use specific availability zone"
  type        = string
  default     = "ru-central1-b"
}

# state находится в облаке

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.61.0"
    }
  }
  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "tf-state-bucket-mentor"
    region     = zone_a
    key        = "project1/lemp.tfstate"
    access_key = "<access_key>"
    secret_key = "<secret_key>"

    skip_region_validation      = true
    skip_credentials_validation = true
  }
}


provider "yandex" {
  service_account_key_file = file("~/key.json")
  cloud_id                 = "id"
  folder_id                = "id"
  zone                     = var.zone_a
}

resource "yandex_vpc_network" "network" {
  name = "network"
}

# Разделить сеть, для отказоустойчивости

resource "yandex_vpc_subnet" "subnet1" {
  name           = "subnet1"
  zone           = var.zone_a
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.50.0/24"]
}


resource "yandex_vpc_subnet" "subnet2" {
  name           = "subnet2"
  zone           = var.zone_b
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.51.0/24"]
}

data "yandex_compute_image" "image_lemp" {
  family = "lemp"
}

data "yandex_compute_image" "image_lamp" {
  family = "lamp"
}


resource "yandex_compute_instance" "vm-1" {
  name = "lemp1"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.image_lemp.id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet1.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}


resource "yandex_compute_instance" "vm-2" {
  name = "lamp2"
  zone = var.zone_b

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.image_lamp.id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet2.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

resource "yandex_lb_target_group" "group_web_1" {
  name      = "my-target-group"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.subnet1.id
    address   = yandex_compute_instance.vm-1.network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.subnet2.id
    address   = yandex_compute_instance.vm-2.network_interface.0.ip_address
  }
}


resource "yandex_lb_network_load_balancer" "web_lb_1" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.group_web_1.id

    healthcheck {
      name = "http"
	  interval            = 2
      timeout             = 1
      unhealthy_threshold = 2
      healthy_threshold   = 2
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

# Информация по структуре. В отдельный файл outputs.tf
# LB - 158.160.53.6
# LEMP - 158.160.62.202
# LAMP - 84.252.139.54

output "internal_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.ip_address
}

output "external_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.nat_ip_address
}

output "internal_address_vm_2" {
  value = yandex_compute_instance.vm-2.network_interface.0.ip_address
}

output "external_address_vm_2" {
  value = yandex_compute_instance.vm-2.network_interface.0.nat_ip_address
}

output "external_load_balancer_1" {
  value = yandex_lb_network_load_balancer.web_lb_1

}
