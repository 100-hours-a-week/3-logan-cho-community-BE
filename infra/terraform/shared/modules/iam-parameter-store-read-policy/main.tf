locals {
  normalized_prefix = trim(var.parameter_path_prefix, "/")
  parameter_arns = [
    "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${local.normalized_prefix}",
    "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${local.normalized_prefix}/*"
  ]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid = "AllowReadParameterStorePath"

    actions = [
      "ssm:DescribeParameters",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]

    resources = local.parameter_arns
  }

  dynamic "statement" {
    for_each = var.enable_kms_decrypt ? [1] : []

    content {
      sid       = "AllowDecryptSecureString"
      actions   = ["kms:Decrypt"]
      resources = var.kms_key_arn == null ? ["*"] : [var.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ssm.${var.aws_region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = var.policy_name
  description = var.policy_description
  policy      = data.aws_iam_policy_document.this.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = var.role_name
  policy_arn = aws_iam_policy.this.arn
}
