output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.this.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.this.arn
}

output "cpu_policy_arn" {
  description = "CPU target tracking policy ARN"
  value       = try(aws_autoscaling_policy.cpu_target[0].arn, null)
}
