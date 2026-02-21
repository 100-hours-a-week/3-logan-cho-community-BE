terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.default_tags
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  default_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Tier        = "three-tier"
    },
    var.tags
  )

  ecr_repository_name = coalesce(var.ecr_repository_name, "${local.name_prefix}-app")
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_ssm_vpc_endpoints = true
  tags                     = local.default_tags
}

module "nat_gateway" {
  source = "../../modules/nat-gateway"

  name                    = local.name_prefix
  public_subnet_ids       = module.vpc.public_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  tags                    = local.default_tags
}

module "sg_alb" {
  source = "../../modules/security-group"

  name             = "${local.name_prefix}-alb-sg"
  description      = "ALB security group"
  vpc_id           = module.vpc.vpc_id
  allow_all_egress = false
  tags             = local.default_tags
}

module "sg_app" {
  source = "../../modules/security-group"

  name             = "${local.name_prefix}-app-sg"
  description      = "App EC2 security group"
  vpc_id           = module.vpc.vpc_id
  allow_all_egress = true
  tags             = local.default_tags
}

module "sg_rds" {
  source = "../../modules/security-group"

  name             = "${local.name_prefix}-rds-sg"
  description      = "RDS security group"
  vpc_id           = module.vpc.vpc_id
  allow_all_egress = false
  tags             = local.default_tags
}

module "sg_redis" {
  source = "../../modules/security-group"

  name             = "${local.name_prefix}-redis-sg"
  description      = "Redis security group"
  vpc_id           = module.vpc.vpc_id
  allow_all_egress = false
  tags             = local.default_tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = module.sg_alb.security_group_id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = module.sg_alb.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = module.sg_app.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = module.sg_app.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = module.sg_alb.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id            = module.sg_rds.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = module.sg_app.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_app" {
  security_group_id            = module.sg_redis.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = module.sg_app.security_group_id
}

resource "aws_ecr_repository" "app" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.default_tags
}

module "iam_app" {
  source = "../../modules/iam"

  role_name             = "${local.name_prefix}-app-role"
  instance_profile_name = "${local.name_prefix}-app-profile"
  additional_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
  tags = local.default_tags
}

module "alb" {
  source = "../../modules/alb"

  name               = "${local.name_prefix}-alb"
  target_group_name  = "${var.environment}-app-tg"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg_alb.security_group_id]
  listener_port      = 80
  target_port        = var.app_port
  health_check_path  = var.health_check_path
  tags               = local.default_tags
}

module "asg" {
  source = "../../modules/asg"

  asg_name                  = "${local.name_prefix}-app-asg"
  launch_template_name      = "${local.name_prefix}-app-lt"
  ami_id                    = var.ami_id
  instance_type             = var.instance_type
  key_name                  = var.key_name
  instance_profile_name     = module.iam_app.instance_profile_name
  security_group_ids        = [module.sg_app.security_group_id]
  private_subnet_ids        = module.vpc.private_subnet_ids
  target_group_arns         = [module.alb.target_group_arn]
  user_data                 = var.app_user_data
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  cpu_target_value          = var.asg_cpu_target
  health_check_type         = "ELB"
  health_check_grace_period = 120

  tags = local.default_tags

  depends_on = [module.nat_gateway]
}

module "rds" {
  source = "../../modules/rds"

  identifier                = "${local.name_prefix}-mysql"
  subnet_group_name         = "${local.name_prefix}-rds-subnet"
  subnet_ids                = module.vpc.private_subnet_ids
  security_group_ids        = [module.sg_rds.security_group_id]
  engine_version            = var.rds_engine_version
  instance_class            = var.rds_instance_class
  allocated_storage         = var.rds_allocated_storage
  max_allocated_storage     = var.rds_max_allocated_storage
  db_name                   = var.rds_db_name
  username                  = var.rds_master_username
  password                  = var.rds_master_password
  multi_az                  = var.rds_multi_az
  backup_retention_period   = var.rds_backup_retention_days
  deletion_protection       = var.rds_deletion_protection
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = var.rds_skip_final_snapshot ? null : var.rds_final_snapshot_identifier
  tags                      = local.default_tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  replication_group_id       = replace("${local.name_prefix}-redis", "_", "-")
  description                = "${local.name_prefix} redis"
  subnet_group_name          = "${local.name_prefix}-redis-subnet"
  subnet_ids                 = module.vpc.private_subnet_ids
  security_group_ids         = [module.sg_redis.security_group_id]
  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_num_cache_clusters
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  multi_az_enabled           = var.redis_multi_az_enabled
  apply_immediately          = var.redis_apply_immediately
  tags                       = local.default_tags
}
