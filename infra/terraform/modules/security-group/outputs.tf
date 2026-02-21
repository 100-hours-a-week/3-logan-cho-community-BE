output "security_group_id" {
  description = "Created security group ID"
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "Created security group ARN"
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "Created security group name"
  value       = aws_security_group.this.name
}
