output "app_instance_id" {
  value = var.enable_app_asg ? null : aws_instance.app[0].id
}

output "app_public_ip" {
  value = var.enable_app_asg ? null : aws_instance.app[0].public_ip
}

output "app_asg_name" {
  value = var.enable_app_asg ? aws_autoscaling_group.app[0].name : null
}

output "app_alb_dns_name" {
  value = var.enable_app_asg ? aws_lb.app[0].dns_name : null
}

output "db_instance_id" {
  value = var.enable_app_asg ? aws_instance.db[0].id : null
}

output "db_public_ip" {
  value = var.enable_app_asg ? aws_instance.db[0].public_ip : null
}

output "db_private_ip" {
  value = var.enable_app_asg ? aws_instance.db[0].private_ip : null
}

output "k6_instance_id" {
  value = aws_instance.k6.id
}

output "k6_public_ip" {
  value = aws_instance.k6.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.experiment.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.experiment.arn
}

output "app_role_name" {
  value = aws_iam_role.app.name
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "k6_security_group_id" {
  value = aws_security_group.k6.id
}

output "db_security_group_id" {
  value = var.enable_app_asg ? aws_security_group.db[0].id : null
}
