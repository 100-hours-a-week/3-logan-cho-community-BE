locals {
  access_domain = length(var.aliases) > 0 ? var.aliases[0] : aws_cloudfront_distribution.this.domain_name
}

output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront default domain name"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "access_domain" {
  description = "Preferred domain for application access"
  value       = local.access_domain
}

output "public_key_id" {
  description = "CloudFront public key ID used by signed cookie"
  value       = aws_cloudfront_public_key.this.id
}

output "key_group_id" {
  description = "Trusted key group ID"
  value       = aws_cloudfront_key_group.this.id
}
