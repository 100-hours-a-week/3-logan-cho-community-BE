variable "name" {
  description = "Security group name"
  type        = string
}

variable "description" {
  description = "Security group description"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the security group is created"
  type        = string
}

variable "allow_all_egress" {
  description = "Whether to allow all outbound traffic"
  type        = bool
  default     = true
}

variable "allow_ipv6_egress" {
  description = "Whether to allow all outbound IPv6 traffic"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
