variable "policy_name" {
  description = "IAM policy name"
  type        = string
}

variable "policy_description" {
  description = "IAM policy description"
  type        = string
  default     = "Object storage permissions for pre-signed URL upload and verification"
}

variable "role_name" {
  description = "IAM role name to attach policy to"
  type        = string
}

variable "bucket_arn" {
  description = "S3 bucket ARN"
  type        = string
}

variable "object_prefixes" {
  description = "Object key prefixes for permission scope"
  type        = list(string)
}

variable "object_actions" {
  description = "Allowed object-level S3 actions"
  type        = list(string)
  default     = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
