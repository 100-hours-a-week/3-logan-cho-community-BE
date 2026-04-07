terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.experiment_name}-${var.version_label}"
  common_tags = merge(
    {
      Project     = var.project_name
      Experiment  = var.experiment_name
      Version     = var.version_label
      ManagedBy   = "terraform"
      Environment = "experiment"
    },
    var.tags
  )
}

module "experiment_base" {
  source = "../../modules/experiment_base"

  project_name                  = var.project_name
  name_prefix                   = local.name_prefix
  aws_region                    = var.aws_region
  vpc_id                        = var.vpc_id
  app_subnet_id                 = var.app_subnet_id
  k6_subnet_id                  = var.k6_subnet_id
  db_subnet_id                  = var.db_subnet_id
  alb_subnet_ids                = var.alb_subnet_ids
  app_asg_subnet_ids            = var.app_asg_subnet_ids
  ssh_allowed_cidrs             = var.ssh_allowed_cidrs
  app_ingress_cidrs             = var.app_ingress_cidrs
  observability_allowed_cidrs   = var.observability_allowed_cidrs
  app_port                      = var.app_port
  app_ami_id                    = var.app_ami_id
  k6_ami_id                     = var.k6_ami_id
  db_ami_id                     = var.db_ami_id
  app_instance_type             = var.app_instance_type
  k6_instance_type              = var.k6_instance_type
  db_instance_type              = var.db_instance_type
  key_name                      = var.key_name
  app_instance_name             = "${local.name_prefix}-app"
  k6_instance_name              = "${local.name_prefix}-k6"
  db_instance_name              = "${local.name_prefix}-db"
  enable_app_asg                = var.enable_app_asg
  app_asg_min_size              = var.app_asg_min_size
  app_asg_max_size              = var.app_asg_max_size
  app_asg_desired_capacity      = var.app_asg_desired_capacity
  app_health_check_path         = var.app_health_check_path
  experiment_ssh_public_key     = var.experiment_ssh_public_key
  s3_bucket_name                = var.s3_bucket_name
  bucket_force_destroy          = var.bucket_force_destroy
  temp_prefix_root              = var.temp_prefix_root
  temp_expiration_days          = var.temp_expiration_days
  app_environment               = var.app_environment
  k6_environment                = var.k6_environment
  app_instance_profile_policies = var.app_instance_profile_policies
  k6_instance_profile_policies  = var.k6_instance_profile_policies
  tags                          = local.common_tags
}

module "async_pipeline" {
  count  = var.enable_async_pipeline ? 1 : 0
  source = "../../modules/async_pipeline"

  name_prefix                    = local.name_prefix
  s3_bucket_arn                  = module.experiment_base.s3_bucket_arn
  lambda_subnet_ids              = var.lambda_subnet_ids
  lambda_security_group_ids      = var.lambda_security_group_ids
  lambda_package_path            = var.lambda_package_path
  lambda_handler                 = var.lambda_handler
  lambda_runtime                 = var.lambda_runtime
  lambda_memory_size             = var.lambda_memory_size
  lambda_timeout                 = var.lambda_timeout
  lambda_reserved_concurrency    = var.lambda_reserved_concurrency
  lambda_batch_size              = var.lambda_batch_size
  lambda_environment             = var.lambda_environment
  sqs_visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  sqs_message_retention_seconds  = var.sqs_message_retention_seconds
  enable_dlq                     = var.enable_dlq
  tags                           = local.common_tags
}

resource "aws_iam_role_policy" "app_async_publish" {
  count = var.enable_async_pipeline ? 1 : 0

  name = "${local.name_prefix}-app-async"
  role = module.experiment_base.app_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:SendMessage"
        ]
        Resource = [module.async_pipeline[0].queue_arn]
      }
    ]
  })
}
