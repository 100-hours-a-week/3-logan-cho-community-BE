locals {
  app_env_lines = [for key, value in var.app_environment : "export ${key}='${replace(value, "'", "'\\''")}'"]
  k6_env_lines  = [for key, value in var.k6_environment : "export ${key}='${replace(value, "'", "'\\''")}'"]

  db_subnet_id       = coalesce(var.db_subnet_id, var.app_subnet_id)
  alb_subnet_ids     = length(var.alb_subnet_ids) > 0 ? var.alb_subnet_ids : distinct([var.app_subnet_id, var.k6_subnet_id])
  app_asg_subnet_ids = length(var.app_asg_subnet_ids) > 0 ? var.app_asg_subnet_ids : [var.app_subnet_id]
  db_ami_id          = coalesce(var.db_ami_id, var.app_ami_id)
  db_instance_name   = coalesce(var.db_instance_name, "${var.name_prefix}-db")
  resource_name_hash = substr(md5(var.name_prefix), 0, 8)
  app_alb_name       = "ip-${local.resource_name_hash}-alb"
  app_tg_name        = "ip-${local.resource_name_hash}-tg"

  app_user_data = <<-EOT
    #!/bin/bash
    set -e
    cat <<'EOF' >/etc/profile.d/experiment-app.sh
    ${join("\n", local.app_env_lines)}
    EOF
    chmod +x /etc/profile.d/experiment-app.sh
    if [ -n "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" ]; then
      install -d -m 700 /home/ec2-user/.ssh
      touch /home/ec2-user/.ssh/authorized_keys
      grep -qxF "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" /home/ec2-user/.ssh/authorized_keys || echo "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" >> /home/ec2-user/.ssh/authorized_keys
      chmod 600 /home/ec2-user/.ssh/authorized_keys
      chown -R ec2-user:ec2-user /home/ec2-user/.ssh
    fi
    if ${var.enable_app_asg}; then
      dnf install -y java-17-amazon-corretto-headless docker
      systemctl enable docker >/dev/null 2>&1 || true
      systemctl restart docker >/dev/null 2>&1 || true
      install -d -m 755 /opt/image-pipeline
      cat <<'EOF' >/usr/local/bin/start-experiment-app.sh
    #!/bin/bash
    set -euo pipefail
    ARTIFACT_ROOT="s3://${var.s3_bucket_name}/artifacts"
    install -d -m 755 /opt/image-pipeline
    aws s3 cp "$${ARTIFACT_ROOT}/experiment-app-env.sh" /opt/image-pipeline/experiment-app-env.sh >/dev/null
    aws s3 cp "$${ARTIFACT_ROOT}/kaboocamPostProject-0.0.1-SNAPSHOT.jar" /opt/image-pipeline/app.jar >/dev/null
    chmod 700 /opt/image-pipeline/experiment-app-env.sh
    pkill -f '/opt/image-pipeline/app.jar' || true
    exec bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >>/opt/image-pipeline/app.log 2>&1'
    EOF
      chmod +x /usr/local/bin/start-experiment-app.sh
      cat <<'EOF' >/etc/systemd/system/experiment-app.service
    [Unit]
    Description=Experiment Spring App
    After=network-online.target docker.service
    Wants=network-online.target docker.service

    [Service]
    Type=simple
    Restart=always
    RestartSec=15
    ExecStart=/usr/local/bin/start-experiment-app.sh

    [Install]
    WantedBy=multi-user.target
    EOF
      systemctl daemon-reload
      systemctl enable experiment-app.service
      systemctl restart experiment-app.service || true
    fi
  EOT

  db_user_data = <<-EOT
    #!/bin/bash
    set -e
    if [ -n "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" ]; then
      install -d -m 700 /home/ec2-user/.ssh
      touch /home/ec2-user/.ssh/authorized_keys
      grep -qxF "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" /home/ec2-user/.ssh/authorized_keys || echo "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" >> /home/ec2-user/.ssh/authorized_keys
      chmod 600 /home/ec2-user/.ssh/authorized_keys
      chown -R ec2-user:ec2-user /home/ec2-user/.ssh
    fi
  EOT
}

resource "aws_security_group" "app" {
  name_prefix = "${var.name_prefix}-app-sg-"
  description = "Security group for experiment app instances"
  vpc_id      = var.vpc_id

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

resource "aws_security_group_rule" "app_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.app.id
  cidr_blocks       = var.ssh_allowed_cidrs
  description       = "Allow SSH to app instances"
}

resource "aws_security_group_rule" "app_from_public" {
  count = var.enable_app_asg ? 0 : 1

  type              = "ingress"
  from_port         = var.app_port
  to_port           = var.app_port
  protocol          = "tcp"
  security_group_id = aws_security_group.app.id
  cidr_blocks       = var.app_ingress_cidrs
  description       = "Allow direct public access to single app instance"
}

resource "aws_security_group" "alb" {
  count = var.enable_app_asg ? 1 : 0

  name_prefix = "${var.name_prefix}-alb-sg-"
  description = "Security group for experiment ALB"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_from_public" {
  count = var.enable_app_asg ? 1 : 0

  type              = "ingress"
  from_port         = var.app_port
  to_port           = var.app_port
  protocol          = "tcp"
  security_group_id = aws_security_group.alb[0].id
  cidr_blocks       = var.app_ingress_cidrs
  description       = "Allow public access to ALB"
}

resource "aws_security_group_rule" "app_from_alb" {
  count = var.enable_app_asg ? 1 : 0

  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.alb[0].id
  description              = "Allow ALB to reach app instances"
}

resource "aws_security_group" "db" {
  count = var.enable_app_asg ? 1 : 0

  name_prefix = "${var.name_prefix}-db-sg-"
  description = "Security group for shared DB instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "db_ssh" {
  count = var.enable_app_asg ? 1 : 0

  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.db[0].id
  cidr_blocks       = var.ssh_allowed_cidrs
  description       = "Allow SSH to DB instance"
}

resource "aws_security_group_rule" "db_mysql_from_app" {
  count = var.enable_app_asg ? 1 : 0

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db[0].id
  source_security_group_id = aws_security_group.app.id
  description              = "Allow app instances to reach MySQL"
}

resource "aws_security_group_rule" "db_mongo_from_app" {
  count = var.enable_app_asg ? 1 : 0

  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db[0].id
  source_security_group_id = aws_security_group.app.id
  description              = "Allow app instances to reach MongoDB"
}

resource "aws_security_group_rule" "db_redis_from_app" {
  count = var.enable_app_asg ? 1 : 0

  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db[0].id
  source_security_group_id = aws_security_group.app.id
  description              = "Allow app instances to reach Redis"
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

resource "aws_iam_role" "db" {
  count = var.enable_app_asg ? 1 : 0

  name = "${var.name_prefix}-db-role"

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

resource "aws_iam_role_policy_attachment" "db_managed" {
  for_each = var.enable_app_asg ? toset(var.app_instance_profile_policies) : toset([])

  role       = aws_iam_role.db[0].name
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

resource "aws_iam_role_policy" "db_s3" {
  count = var.enable_app_asg ? 1 : 0

  name = "${var.name_prefix}-db-s3"
  role = aws_iam_role.db[0].id

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

resource "aws_iam_instance_profile" "db" {
  count = var.enable_app_asg ? 1 : 0

  name = "${var.name_prefix}-db-profile"
  role = aws_iam_role.db[0].name
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
  count = var.enable_app_asg ? 0 : 1

  ami                         = var.app_ami_id
  instance_type               = var.app_instance_type
  subnet_id                   = var.app_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true
  user_data                   = local.app_user_data

  tags = merge(var.tags, { Name = var.app_instance_name, Role = "app" })
}

resource "aws_instance" "db" {
  count = var.enable_app_asg ? 1 : 0

  ami                         = local.db_ami_id
  instance_type               = var.db_instance_type
  subnet_id                   = local.db_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.db[0].id]
  iam_instance_profile        = aws_iam_instance_profile.db[0].name
  associate_public_ip_address = true
  user_data                   = local.db_user_data

  tags = merge(var.tags, { Name = local.db_instance_name, Role = "db" })
}

resource "aws_launch_template" "app" {
  count = var.enable_app_asg ? 1 : 0

  name_prefix   = "${var.name_prefix}-app-lt-"
  image_id      = var.app_ami_id
  instance_type = var.app_instance_type
  key_name      = var.key_name
  user_data     = base64encode(local.app_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = var.app_instance_name
      Role = "app"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "app" {
  count = var.enable_app_asg ? 1 : 0

  name               = local.app_alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = local.alb_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-alb" })
}

resource "aws_lb_target_group" "app" {
  count = var.enable_app_asg ? 1 : 0

  name        = local.app_tg_name
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.app_health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 20
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-tg" })
}

resource "aws_lb_listener" "app" {
  count = var.enable_app_asg ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = var.app_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}

resource "aws_autoscaling_group" "app" {
  count = var.enable_app_asg ? 1 : 0

  name                      = "${var.name_prefix}-app-asg"
  min_size                  = var.app_asg_min_size
  max_size                  = var.app_asg_max_size
  desired_capacity          = var.app_asg_desired_capacity
  vpc_zone_identifier       = local.app_asg_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 120
  target_group_arns         = [aws_lb_target_group.app[0].arn]

  launch_template {
    id      = aws_launch_template.app[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = var.app_instance_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
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
    if [ -n "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" ]; then
      install -d -m 700 /home/ec2-user/.ssh
      touch /home/ec2-user/.ssh/authorized_keys
      grep -qxF "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" /home/ec2-user/.ssh/authorized_keys || echo "${replace(var.experiment_ssh_public_key, "\"", "\\\"")}" >> /home/ec2-user/.ssh/authorized_keys
      chmod 600 /home/ec2-user/.ssh/authorized_keys
      chown -R ec2-user:ec2-user /home/ec2-user/.ssh
    fi
  EOT

  tags = merge(var.tags, { Name = var.k6_instance_name, Role = "k6" })
}
