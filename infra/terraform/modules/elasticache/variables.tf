variable "replication_group_id" {
  description = "ElastiCache replication group ID"
  type        = string
}

variable "description" {
  description = "ElastiCache replication group description"
  type        = string
}

variable "subnet_group_name" {
  description = "ElastiCache subnet group name"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for ElastiCache"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups attached to Redis"
  type        = list(string)
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "node_type" {
  description = "Cache node instance type"
  type        = string
}

variable "port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "num_cache_clusters" {
  description = "Number of cache clusters"
  type        = number
  default     = 2
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ for Redis"
  type        = bool
  default     = true
}

variable "at_rest_encryption_enabled" {
  description = "Enable at-rest encryption"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Enable in-transit encryption"
  type        = bool
  default     = true
}

variable "snapshot_retention_limit" {
  description = "Snapshot retention limit in days"
  type        = number
  default     = 1
}

variable "apply_immediately" {
  description = "Apply modifications immediately"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
