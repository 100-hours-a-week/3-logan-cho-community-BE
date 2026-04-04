output "app_instance_id" {
  value = module.experiment_base.app_instance_id
}

output "app_public_ip" {
  value = module.experiment_base.app_public_ip
}

output "k6_instance_id" {
  value = module.experiment_base.k6_instance_id
}

output "k6_public_ip" {
  value = module.experiment_base.k6_public_ip
}

output "s3_bucket_name" {
  value = module.experiment_base.s3_bucket_name
}

output "app_security_group_id" {
  value = module.experiment_base.app_security_group_id
}

output "k6_security_group_id" {
  value = module.experiment_base.k6_security_group_id
}

output "grafana_url" {
  value = "http://${module.experiment_base.k6_public_ip}:3000"
}

output "prometheus_url" {
  value = "http://${module.experiment_base.k6_public_ip}:9090"
}

output "sqs_queue_url" {
  value = var.enable_async_pipeline ? module.async_pipeline[0].queue_url : null
}

output "sqs_queue_arn" {
  value = var.enable_async_pipeline ? module.async_pipeline[0].queue_arn : null
}

output "lambda_function_name" {
  value = var.enable_async_pipeline ? module.async_pipeline[0].lambda_function_name : null
}

output "dlq_url" {
  value = var.enable_dlq && var.enable_async_pipeline ? module.async_pipeline[0].dlq_url : null
}
