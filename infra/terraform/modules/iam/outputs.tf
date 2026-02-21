output "role_name" {
  description = "EC2 role name"
  value       = aws_iam_role.ec2.name
}

output "role_arn" {
  description = "EC2 role ARN"
  value       = aws_iam_role.ec2.arn
}

output "instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2.name
}

output "instance_profile_arn" {
  description = "EC2 instance profile ARN"
  value       = aws_iam_instance_profile.ec2.arn
}
