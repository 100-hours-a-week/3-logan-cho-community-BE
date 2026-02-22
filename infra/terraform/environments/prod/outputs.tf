output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "app_asg_name" {
  description = "Application Auto Scaling Group name"
  value       = module.asg.asg_name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = module.elasticache.primary_endpoint_address
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "media_bucket_name" {
  description = "Media S3 bucket name"
  value       = module.private_content_delivery.bucket_name
}

output "media_cloudfront_domain" {
  description = "CloudFront domain used by application"
  value       = module.private_content_delivery.access_domain
}

output "media_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for private media"
  value       = module.private_content_delivery.distribution_id
}

output "media_parameter_names" {
  description = "SSM parameter names created for media config"
  value       = module.media_parameter_store.all_parameter_names
}
