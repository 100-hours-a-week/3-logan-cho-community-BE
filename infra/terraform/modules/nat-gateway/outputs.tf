output "nat_gateway_ids" {
  description = "NAT gateway IDs"
  value       = [for idx in sort(keys(aws_nat_gateway.this)) : aws_nat_gateway.this[idx].id]
}

output "elastic_ip_ids" {
  description = "Elastic IP allocation IDs for NAT gateways"
  value       = [for idx in sort(keys(aws_eip.this)) : aws_eip.this[idx].id]
}
