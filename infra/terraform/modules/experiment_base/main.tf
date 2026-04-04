locals {
  app_env_lines = [for key, value in var.app_environment : "export ${key}='${replace(value, "'", "'\\''")}'"]
  k6_env_lines  = [for key, value in var.k6_environment : "export ${key}='${replace(value, "'", "'\\''")}'"]
}

resource "aws_security_group" "app" {
  name_prefix = "${var.name_prefix}-app-sg-"
  description = "Security group for experiment app instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = var.app_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "k6" {
  name_prefix = "${var.name_prefix}-k6-sg-"
  description = "Security group for experiment k6 instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.observability_allowed_cidrs
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.observability_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-k6-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "app_node_exporter_from_k6" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.k6.id
  description              = "Allow Prometheus on k6 instance to scrape node_exporter"
}

resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role" "k6" {
  name = "${var.name_prefix}-k6-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "app_managed" {
  for_each = toset(var.app_instance_profile_policies)

  role       = aws_iam_role.app.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "k6_managed" {
  for_each = toset(var.k6_instance_profile_policies)

  role       = aws_iam_role.k6.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "app_s3" {
  name = "${var.name_prefix}-app-s3"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.experiment.arn,
          "${aws_s3_bucket.experiment.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "k6_s3" {
  name = "${var.name_prefix}-k6-s3"
  role = aws_iam_role.k6.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.experiment.arn,
          "${aws_s3_bucket.experiment.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_iam_instance_profile" "k6" {
  name = "${var.name_prefix}-k6-profile"
  role = aws_iam_role.k6.name
}

resource "aws_s3_bucket" "experiment" {
  bucket        = var.s3_bucket_name
  force_destroy = var.bucket_force_destroy
  tags          = merge(var.tags, { Name = var.s3_bucket_name })
}

resource "aws_s3_bucket_versioning" "experiment" {
  bucket = aws_s3_bucket.experiment.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "experiment" {
  bucket = aws_s3_bucket.experiment.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "experiment" {
  bucket = aws_s3_bucket.experiment.id

  rule {
    id     = "expire-temp-objects"
    status = "Enabled"

    filter {
      prefix = var.temp_prefix_root
    }

    expiration {
      days = var.temp_expiration_days
    }
  }
}

resource "aws_instance" "app" {
  ami                         = var.app_ami_id
  instance_type               = var.app_instance_type
  subnet_id                   = var.app_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -e
    cat <<'EOF' >/etc/profile.d/experiment-app.sh
    ${join("\n", local.app_env_lines)}
    EOF
    chmod +x /etc/profile.d/experiment-app.sh
  EOT

  tags = merge(var.tags, { Name = var.app_instance_name, Role = "app" })
}

resource "aws_instance" "k6" {
  ami                         = var.k6_ami_id
  instance_type               = var.k6_instance_type
  subnet_id                   = var.k6_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k6.id]
  iam_instance_profile        = aws_iam_instance_profile.k6.name
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -e
    cat <<'EOF' >/etc/profile.d/experiment-k6.sh
    ${join("\n", local.k6_env_lines)}
    EOF
    chmod +x /etc/profile.d/experiment-k6.sh
  EOT

  tags = merge(var.tags, { Name = var.k6_instance_name, Role = "k6" })
}
