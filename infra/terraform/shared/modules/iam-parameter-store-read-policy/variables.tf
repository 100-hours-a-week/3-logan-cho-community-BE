variable "policy_name" {
  description = "IAM policy name"
  type        = string
}

variable "policy_description" {
  description = "IAM policy description"
  type        = string
  default     = "Read access to SSM Parameter Store path"
}

variable "role_name" {
  description = "IAM role name to attach policy to"
  type        = string
}

variable "aws_region" {
  description = "AWS region used for ARN construction"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID used for ARN construction"
  type        = string
}

variable "parameter_path_prefix" {
  description = "SSM parameter path prefix (e.g. /app/backend)"
  type        = string
}

variable "enable_kms_decrypt" {
  description = "Allow kms:Decrypt for SecureString parameters"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for decrypt permission"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
