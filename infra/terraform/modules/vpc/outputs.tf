output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs ordered by availability_zones"
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs ordered by availability_zones"
  value       = [for az in var.availability_zones : aws_subnet.private[az].id]
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Private route table IDs ordered by availability_zones"
  value       = [for az in var.availability_zones : aws_route_table.private[az].id]
}

output "ssm_vpc_endpoint_ids" {
  description = "Interface endpoint IDs for SSM services"
  value       = { for k, endpoint in aws_vpc_endpoint.ssm_interface : k => endpoint.id }
}

output "ssm_endpoint_security_group_id" {
  description = "Security group ID attached to SSM interface endpoints"
  value       = try(aws_security_group.ssm_endpoint[0].id, null)
}
