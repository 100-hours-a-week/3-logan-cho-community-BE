variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
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
}

variable "admin_ssh_key_path" {
  description = "Path to the SSH public key file used for VM login."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to connect over SSH."
  type        = list(string)
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
