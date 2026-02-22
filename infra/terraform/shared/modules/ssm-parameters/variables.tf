variable "path_prefix" {
  description = "SSM parameter path prefix (e.g. /app/backend)"
  type        = string
}

variable "string_parameters" {
  description = "Map of String parameters"
  type        = map(string)
  default     = {}
}

variable "secure_string_parameters" {
  description = "Map of SecureString parameters"
  type        = map(string)
  default     = {}
}

variable "kms_key_id" {
  description = "Optional KMS key ID/ARN for SecureString encryption"
  type        = string
  default     = null
}

variable "overwrite" {
  description = "Whether to overwrite existing parameters"
  type        = bool
  default     = true
}

variable "tier" {
  description = "Parameter tier"
  type        = string
  default     = "Standard"
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
