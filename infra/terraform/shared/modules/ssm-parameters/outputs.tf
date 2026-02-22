output "string_parameter_names" {
  description = "Names of created String parameters"
  value       = { for k, v in aws_ssm_parameter.string : k => v.name }
}

output "secure_parameter_names" {
  description = "Names of created SecureString parameters"
  value       = { for k, v in aws_ssm_parameter.secure_string : k => v.name }
}

output "all_parameter_names" {
  description = "All created parameter names"
  value = concat(
    [for p in aws_ssm_parameter.string : p.name],
    [for p in aws_ssm_parameter.secure_string : p.name]
  )
}
