locals {
  normalized_prefix = trimsuffix(var.path_prefix, "/")
}

resource "aws_ssm_parameter" "string" {
  for_each = var.string_parameters

  name        = "${local.normalized_prefix}/${each.key}"
  description = "Managed by Terraform"
  type        = "String"
  value       = each.value
  overwrite   = var.overwrite
  tier        = var.tier

  tags = var.tags
}

resource "aws_ssm_parameter" "secure_string" {
  for_each = var.secure_string_parameters

  name        = "${local.normalized_prefix}/${each.key}"
  description = "Managed by Terraform"
  type        = "SecureString"
  value       = each.value
  key_id      = var.kms_key_id
  overwrite   = var.overwrite
  tier        = var.tier

  tags = var.tags
}
