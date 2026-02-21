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
