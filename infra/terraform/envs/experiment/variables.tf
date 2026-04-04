variable "project_name" {
  type    = string
  default = "community-be"
}

variable "experiment_name" {
  type    = string
  default = "image-pipeline-evolution"
}

variable "version_label" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_id" {
  type = string
}

variable "k6_subnet_id" {
  type = string
}

variable "ssh_allowed_cidrs" {
  type = list(string)
}

variable "app_ingress_cidrs" {
  type = list(string)
}

variable "observability_allowed_cidrs" {
  type = list(string)
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "app_ami_id" {
  type = string
}

variable "k6_ami_id" {
  type = string
}

variable "app_instance_type" {
  type = string
}

variable "k6_instance_type" {
  type = string
}

variable "key_name" {
  type    = string
  default = null
}

variable "s3_bucket_name" {
  type = string
}

variable "bucket_force_destroy" {
  type    = bool
  default = false
}

variable "temp_prefix_root" {
  type    = string
  default = "experiments/temp/"
}

variable "temp_expiration_days" {
  type    = number
  default = 2
}

variable "app_environment" {
  type    = map(string)
  default = {}
}

variable "k6_environment" {
  type    = map(string)
  default = {}
}

variable "app_instance_profile_policies" {
  type    = list(string)
  default = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

variable "k6_instance_profile_policies" {
  type    = list(string)
  default = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

variable "enable_async_pipeline" {
  type    = bool
  default = false
}

variable "enable_dlq" {
  type    = bool
  default = false
}

variable "lambda_subnet_ids" {
  type    = list(string)
  default = []
}

variable "lambda_security_group_ids" {
  type    = list(string)
  default = []
}

variable "lambda_package_path" {
  type    = string
  default = null
}

variable "lambda_handler" {
  type    = string
  default = "bootstrap"
}

variable "lambda_runtime" {
  type    = string
  default = "provided.al2"
}

variable "lambda_memory_size" {
  type    = number
  default = 1024
}

variable "lambda_timeout" {
  type    = number
  default = 30
}

variable "lambda_reserved_concurrency" {
  type    = number
  default = 2
}

variable "lambda_batch_size" {
  type    = number
  default = 1
}

variable "lambda_environment" {
  type    = map(string)
  default = {}
}

variable "sqs_visibility_timeout_seconds" {
  type    = number
  default = 120
}

variable "sqs_message_retention_seconds" {
  type    = number
  default = 345600
}

variable "tags" {
  type    = map(string)
  default = {}
}
