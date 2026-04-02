variable "enable_azure" {
  description = "Whether to create the Azure Busan benchmark VM."
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region for the benchmark VM."
  type        = string
  default     = "koreasouth"
}

variable "vm_name" {
  description = "Virtual machine name."
  type        = string
  default     = "cf-benchmark-vm"
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Linux admin username."
  type        = string
  default     = ""
}

variable "admin_ssh_key_path" {
  description = "Path to the SSH public key file used for VM login."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to connect over SSH."
  type        = list(string)
  default     = []
}

variable "address_space" {
  description = "VNet CIDR."
  type        = list(string)
  default     = ["10.90.0.0/16"]
}

variable "subnet_prefixes" {
  description = "Subnet CIDR list."
  type        = list(string)
  default     = ["10.90.1.0/24"]
}

variable "tags" {
  description = "Common Azure tags."
  type        = map(string)
  default = {
    project = "cf-private-content-benchmark"
  }
}

variable "enable_experimental_stack" {
  description = "Whether to create the experimental AWS S3 + CloudFront private content stack."
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region for the S3 bucket that backs the experimental stack."
  type        = string
  default     = "ap-northeast-2"
}

variable "experiment_name_prefix" {
  description = "Prefix for the experimental AWS stack resources."
  type        = string
  default     = "cf-private-benchmark"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class for the experimental stack."
  type        = string
  default     = "PriceClass_200"
}

variable "benchmark_miss_iterations" {
  description = "How many unique miss objects to create per size case."
  type        = number
  default     = 20
}

variable "benchmark_hit_iterations" {
  description = "How many hit iterations the generated config should use."
  type        = number
  default     = 30
}

variable "object_sizes_bytes" {
  description = "Object sizes in bytes for each logical benchmark size case."
  type        = map(number)
  default = {
    small  = 24576
    medium = 196608
    large  = 819200
  }
}

variable "signed_url_ttl_seconds" {
  description = "TTL for generated S3 pre-signed URLs and CloudFront signed URLs."
  type        = number
  default     = 7200
}

variable "cookie_ttl_seconds_miss" {
  description = "TTL for CloudFront signed cookies used in miss runs."
  type        = number
  default     = 7200
}

variable "cookie_ttl_seconds_hit" {
  description = "TTL for CloudFront signed cookies used in hit runs."
  type        = number
  default     = 7200
}

variable "bootstrap_server_host" {
  description = "Host for the local or remote cookie bootstrap server."
  type        = string
  default     = "127.0.0.1"
}

variable "bootstrap_server_port" {
  description = "Port for the local or remote cookie bootstrap server."
  type        = number
  default     = 3100
}
