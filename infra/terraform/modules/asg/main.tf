locals {
  launch_template_user_data = var.user_data == null ? null : base64encode(var.user_data)

  asg_tags = merge(var.tags, var.asg_tags, {
    Name = var.asg_name
  })
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.launch_template_name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = local.launch_template_user_data

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_group_ids
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = var.http_tokens
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.asg_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.asg_tags
  }

  tags = local.asg_tags
}

resource "aws_autoscaling_group" "this" {
  name                      = var.asg_name
  max_size                  = var.max_size
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = var.target_group_arns

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = local.asg_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_policy" "cpu_target" {
  count = var.enable_cpu_target_tracking ? 1 : 0

  name                   = "${var.asg_name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
  }

  estimated_instance_warmup = var.cpu_warmup_seconds
}
