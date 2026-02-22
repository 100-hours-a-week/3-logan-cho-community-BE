variable "aws_region" {
  type        = string
  default     = "ap-northeast-2"
  description = "AWS region used to build AMI"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Builder instance type"
}

variable "ami_name_prefix" {
  type        = string
  default     = "kaboocam-post-golden-ami"
  description = "Prefix used in generated AMI name"
}

variable "source_ami_filter_name" {
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
  description = "Source AMI name pattern"
}

variable "source_ami_owner" {
  type        = string
  default     = "099720109477"
  description = "Source AMI owner (Canonical)"
}

variable "ssh_username" {
  type        = string
  default     = "ubuntu"
  description = "SSH user for packer builder"
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "Optional builder VPC ID"
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Optional builder subnet ID"
}

variable "security_group_id" {
  type        = string
  default     = ""
  description = "Optional builder security group ID"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "kaboocam-post"
    Environment = "common"
    ManagedBy   = "packer"
  }
  description = "Tags applied to AMI and snapshots"
}

variable "loki_url" {
  type        = string
  default     = "http://loki:3100/loki/api/v1/push"
  description = "Promtail push endpoint"
}
