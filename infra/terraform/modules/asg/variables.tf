variable "asg_name" {
  description = "Auto Scaling Group name"
  type        = string
}

variable "launch_template_name" {
  description = "Launch template name prefix"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "Optional SSH key pair name"
  type        = string
  default     = null
}

variable "instance_profile_name" {
  description = "IAM instance profile name for EC2 instances"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs attached to app instances"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ASG placement"
  type        = list(string)
}

variable "target_group_arns" {
  description = "ALB target group ARNs"
  type        = list(string)
}

variable "user_data" {
  description = "User data script (plain text)"
  type        = string
  default     = null
}

variable "min_size" {
  description = "ASG minimum capacity"
  type        = number
}

variable "max_size" {
  description = "ASG maximum capacity"
  type        = number
}

variable "desired_capacity" {
  description = "ASG desired capacity"
  type        = number
}

variable "health_check_type" {
  description = "ASG health check type"
  type        = string
  default     = "ELB"
}

variable "health_check_grace_period" {
  description = "ASG health check grace period in seconds"
  type        = number
  default     = 300
}

variable "enable_cpu_target_tracking" {
  description = "Enable target tracking scaling policy on CPU"
  type        = bool
  default     = true
}

variable "cpu_target_value" {
  description = "Target average CPU utilization percentage"
  type        = number
  default     = 60
}

variable "cpu_warmup_seconds" {
  description = "Estimated instance warmup in seconds"
  type        = number
  default     = 120
}

variable "http_tokens" {
  description = "IMDSv2 setting for launch template"
  type        = string
  default     = "required"
}

variable "tags" {
  description = "Base tags applied to resources"
  type        = map(string)
  default     = {}
}

variable "asg_tags" {
  description = "Additional ASG tags"
  type        = map(string)
  default     = {}
}
