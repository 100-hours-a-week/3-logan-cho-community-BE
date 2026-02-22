variable "name" {
  description = "ALB name"
  type        = string
}

variable "target_group_name" {
  description = "ALB target group name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for target group"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs where ALB is deployed"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups attached to ALB"
  type        = list(string)
}

variable "internal" {
  description = "Whether ALB is internal"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "listener_port" {
  description = "ALB listener port"
  type        = number
  default     = 80
}

variable "listener_protocol" {
  description = "ALB listener protocol"
  type        = string
  default     = "HTTP"
}

variable "target_port" {
  description = "Target group backend port"
  type        = number
}

variable "target_protocol" {
  description = "Target group protocol"
  type        = string
  default     = "HTTP"
}

variable "target_type" {
  description = "Target type for target group"
  type        = string
  default     = "instance"
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/actuator/health"
}

variable "health_check_matcher" {
  description = "HTTP codes considered healthy"
  type        = string
  default     = "200-399"
}

variable "health_check_interval" {
  description = "Health check interval seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Healthy threshold count"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Unhealthy threshold count"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}
