locals {
  normalized_prefixes = [for prefix in var.object_prefixes : trim(prefix, "/")]
  object_arns         = [for prefix in local.normalized_prefixes : "${var.bucket_arn}/${prefix}/*"]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "AllowObjectAccessForPresignedFlow"
    actions   = var.object_actions
    resources = local.object_arns
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
