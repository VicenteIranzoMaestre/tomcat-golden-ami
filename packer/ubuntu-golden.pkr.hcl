packer {
  required_version = ">= 1.10.0"
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ubuntu_series" {
  type    = string
  description = "Ubuntu series to build: jammy (22.04) or noble (24.04)"
  default = "jammy"
}

variable "user_app_name" {
  type    = string
  default = "wiris"
}

variable "user_context_path" {
  type    = string
  default = ""
}

variable "user_war_url" {
  type    = string
  default = ""
}

variable "user_war_checksum" {
  type    = string
  default = ""
}

locals {
  source_filter_name = var.ubuntu_series == "noble" ?
    "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" :
    "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

source "amazon-ebs" "ubuntu" {
  region                  = var.region
  instance_type           = var.instance_type
  ami_name                = "golden-tomcat-${var.ubuntu_series}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  ami_description         = "Golden AMI with Tomcat and pre-deployed app via Ansible"
  associate_public_ip_address = true
  ssh_username            = "ubuntu"

  # Find the latest Ubuntu AMI from Canonical
  source_ami_filter {
    filters = {
      name                = local.source_filter_name
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  # Clean up
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 12
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "golden-tomcat-${var.ubuntu_series}"
    BuildTool   = "Packer"
    ManagedBy   = "GitHubActions"
  }
}

build {
  name    = "golden-ami-${var.ubuntu_series}"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y python3 python3-apt"
    ]
  }

  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
    user          = "ubuntu"
    groups        = ["default"]
    extra_arguments = [
      "--extra-vars",
      "user_app_name=${var.user_app_name} user_context_path=${var.user_context_path} user_war_url=${var.user_war_url} user_war_checksum=${var.user_war_checksum}"
    ]
  }

  # Optional: minimize the image
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*"
    ]
  }
}
