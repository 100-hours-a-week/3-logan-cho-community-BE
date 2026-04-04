variable "project_name" { type = string }
variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "app_subnet_id" { type = string }
variable "k6_subnet_id" { type = string }
variable "ssh_allowed_cidrs" { type = list(string) }
variable "app_ingress_cidrs" { type = list(string) }
variable "observability_allowed_cidrs" { type = list(string) }
variable "app_port" { type = number }
variable "app_ami_id" { type = string }
variable "k6_ami_id" { type = string }
variable "app_instance_type" { type = string }
variable "k6_instance_type" { type = string }
variable "key_name" {
  type    = string
  default = null
}
variable "app_instance_name" { type = string }
variable "k6_instance_name" { type = string }
variable "s3_bucket_name" { type = string }
variable "bucket_force_destroy" { type = bool }
variable "temp_prefix_root" { type = string }
variable "temp_expiration_days" { type = number }
variable "app_environment" {
  type    = map(string)
  default = {}
}
variable "k6_environment" {
  type    = map(string)
  default = {}
}
variable "app_instance_profile_policies" {
  type = list(string)
}
variable "k6_instance_profile_policies" {
  type = list(string)
}
variable "tags" {
  type    = map(string)
  default = {}
}
