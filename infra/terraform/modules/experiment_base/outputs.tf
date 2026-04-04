output "app_instance_id" {
  value = aws_instance.app.id
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
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
