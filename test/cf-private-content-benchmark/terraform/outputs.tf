output "vm_public_ip" {
  description = "Public IPv4 address of the Azure Busan benchmark VM."
  value       = null
}

output "ssh_command" {
  description = "SSH command for the benchmark VM."
  value       = null
}

output "run_remote_command" {
  description = "Example command to copy the benchmark workspace and run the remote benchmark."
  value       = null
}

output "experiment_bucket_name" {
  description = "Experimental S3 bucket name."
  value       = var.enable_experimental_stack ? aws_s3_bucket.experiment[0].bucket : null
}

output "experiment_cloudfront_domain_name" {
  description = "Experimental CloudFront distribution domain name."
  value       = var.enable_experimental_stack ? aws_cloudfront_distribution.experiment[0].domain_name : null
}

output "experiment_cloudfront_distribution_id" {
  description = "Experimental CloudFront distribution ID."
  value       = var.enable_experimental_stack ? aws_cloudfront_distribution.experiment[0].id : null
}

output "experiment_cloudfront_public_key_id" {
  description = "CloudFront public key ID to use as Key-Pair-Id for signed URLs and cookies."
  value       = var.enable_experimental_stack ? aws_cloudfront_public_key.experiment[0].id : null
}

output "experiment_private_key_pem_path" {
  description = "Local path to the generated CloudFront private key PEM."
  value       = var.enable_experimental_stack ? local_sensitive_file.experiment_private_key[0].filename : null
  sensitive   = true
}

output "experiment_object_manifest" {
  description = "Object manifest grouped by size case and phase for benchmark config generation."
  value       = var.enable_experimental_stack ? local.benchmark_object_manifest : null
}

output "experiment_aws_region" {
  description = "AWS region used by the experimental stack."
  value       = var.aws_region
}

output "benchmark_miss_iterations" {
  description = "Miss iterations used by the generated benchmark config."
  value       = var.benchmark_miss_iterations
}

output "benchmark_hit_iterations" {
  description = "Hit iterations used by the generated benchmark config."
  value       = var.benchmark_hit_iterations
}

output "signed_url_ttl_seconds" {
  description = "Signed URL TTL in seconds."
  value       = var.signed_url_ttl_seconds
}

output "cookie_ttl_seconds_miss" {
  description = "Signed cookie TTL in seconds for miss runs."
  value       = var.cookie_ttl_seconds_miss
}

output "cookie_ttl_seconds_hit" {
  description = "Signed cookie TTL in seconds for hit runs."
  value       = var.cookie_ttl_seconds_hit
}

output "cookie_bootstrap_url_example" {
  description = "Example bootstrap server URL to embed into benchmark.config.json."
  value       = "http://${var.bootstrap_server_host}:${var.bootstrap_server_port}/issue-cookie"
}
