variable "role_name" {
  description = "IAM role name for EC2 instances"
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile name used by EC2 launch template"
  type        = string
}

variable "ssm_managed_policy_arn" {
  description = "Managed policy ARN for AWS Systems Manager access"
  type        = string
  default     = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

variable "additional_managed_policy_arns" {
  description = "Additional managed policies attached to EC2 role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
