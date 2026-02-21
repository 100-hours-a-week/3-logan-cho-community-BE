variable "name" {
  description = "Name prefix for NAT resources"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs where NAT gateways are deployed"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Private route table IDs that should route outbound traffic to NAT"
  type        = list(string)
}

variable "private_default_route_cidr" {
  description = "Default route CIDR for private route tables"
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
