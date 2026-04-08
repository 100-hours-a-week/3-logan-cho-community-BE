variable "name_prefix" { type = string }
variable "s3_bucket_arn" { type = string }
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
variable "lambda_handler" { type = string }
variable "lambda_runtime" { type = string }
variable "lambda_memory_size" { type = number }
variable "lambda_timeout" { type = number }
variable "lambda_reserved_concurrency" { type = number }
variable "lambda_batch_size" { type = number }
variable "lambda_environment" {
  type    = map(string)
  default = {}
}
variable "sqs_visibility_timeout_seconds" { type = number }
variable "sqs_message_retention_seconds" { type = number }
variable "enable_dlq" { type = bool }
variable "tags" {
  type    = map(string)
  default = {}
}
