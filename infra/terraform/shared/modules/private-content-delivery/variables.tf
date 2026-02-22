variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "bucket_name" {
  description = "Private S3 bucket name for object storage"
  type        = string
}

variable "bucket_force_destroy" {
  description = "Whether to force-destroy bucket objects on deletion"
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "Allowed origins for browser uploads via pre-signed URL"
  type        = list(string)
  default     = []
}

variable "read_object_prefixes" {
  description = "Object path patterns readable through CloudFront"
  type        = list(string)
  default     = ["public/images/*"]
}

variable "cloudfront_public_key_pem" {
  description = "CloudFront public key in PEM format"
  type        = string
}

variable "public_key_name" {
  description = "Optional override for CloudFront public key name"
  type        = string
  default     = null
}

variable "key_group_name" {
  description = "Optional override for CloudFront key group name"
  type        = string
  default     = null
}

variable "aliases" {
  description = "Optional CloudFront alias domains"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront aliases"
  type        = string
  default     = null
}

variable "minimum_protocol_version" {
  description = "Minimum TLS version for custom certificate"
  type        = string
  default     = "TLSv1.2_2021"
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_200"
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
