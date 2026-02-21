provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default     = {}
}
