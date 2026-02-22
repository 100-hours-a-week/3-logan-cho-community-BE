packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
  }
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
  ami_name  = "${var.ami_name_prefix}-${local.timestamp}"
}

source "amazon-ebs" "ubuntu" {
  ami_name        = local.ami_name
  ami_description = "Kaboocam Golden AMI - Docker/SSM/ECR helper and base runtime files"
  region          = var.aws_region
  instance_type   = var.instance_type

  source_ami_filter {
    filters = {
      name                = var.source_ami_filter_name
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }
    owners      = [var.source_ami_owner]
    most_recent = true
  }

  ssh_username = var.ssh_username

  vpc_id            = var.vpc_id != "" ? var.vpc_id : null
  subnet_id         = var.subnet_id != "" ? var.subnet_id : null
  security_group_id = var.security_group_id != "" ? var.security_group_id : null

  associate_public_ip_address = true

  tags = merge(var.tags, {
    Name      = local.ami_name
    BuildTime = local.timestamp
  })

  snapshot_tags = var.tags

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "kaboocam-golden-ami"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/monitoring",
      "mkdir -p /tmp/app"
    ]
  }

  provisioner "file" {
    source      = "files/monitoring/"
    destination = "/tmp/monitoring/"
  }

  provisioner "file" {
    source      = "files/app/"
    destination = "/tmp/app/"
  }

  provisioner "file" {
    source      = "files/systemd/monitoring.service"
    destination = "/tmp/monitoring.service"
  }

  provisioner "file" {
    source      = "files/systemd/app.service"
    destination = "/tmp/app.service"
  }

  provisioner "shell" {
    script = "scripts/setup.sh"
    environment_vars = [
      "LOKI_URL=${var.loki_url}"
    ]
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "chmod +x {{ .Path }}; sudo bash '{{ .Path }}'"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
