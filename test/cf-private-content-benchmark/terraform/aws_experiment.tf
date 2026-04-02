locals {
  generated_dir         = "${path.module}/generated"
  generated_objects_dir = "${local.generated_dir}/objects"

  size_case_names = sort(keys(var.object_sizes_bytes))

  experiment_object_defs = merge([
    for size_case, size_bytes in var.object_sizes_bytes : merge(
      {
        for index in range(var.benchmark_miss_iterations) :
        "${size_case}-miss-${format("%02d", index + 1)}" => {
          size_case  = size_case
          phase      = "miss"
          iteration  = index + 1
          size_bytes = size_bytes
          key        = "benchmark/${size_case}/miss/${size_case}-miss-${format("%02d", index + 1)}.bin"
          label      = "${size_case}-miss-${format("%02d", index + 1)}"
        }
      },
      {
        "${size_case}-hit" = {
          size_case  = size_case
          phase      = "hit"
          iteration  = 1
          size_bytes = size_bytes
          key        = "benchmark/${size_case}/hit/${size_case}-hit.bin"
          label      = "${size_case}-hit"
        }
      }
    )
  ]...)

  experiment_object_file_paths = {
    for object_id, object_def in local.experiment_object_defs :
    object_id => "${local.generated_objects_dir}/${object_def.key}"
  }

  benchmark_object_manifest = {
    for size_case in local.size_case_names : size_case => {
      miss = [
        for object_id in sort([
          for candidate_id, candidate in local.experiment_object_defs :
          candidate_id if candidate.size_case == size_case && candidate.phase == "miss"
          ]) : {
          objectId  = object_id
          key       = local.experiment_object_defs[object_id].key
          label     = local.experiment_object_defs[object_id].label
          sizeBytes = local.experiment_object_defs[object_id].size_bytes
        }
      ]
      hit = [
        for object_id in sort([
          for candidate_id, candidate in local.experiment_object_defs :
          candidate_id if candidate.size_case == size_case && candidate.phase == "hit"
          ]) : {
          objectId  = object_id
          key       = local.experiment_object_defs[object_id].key
          label     = local.experiment_object_defs[object_id].label
          sizeBytes = local.experiment_object_defs[object_id].size_bytes
        }
      ]
    }
  }
}

resource "random_string" "experiment_suffix" {
  count   = var.enable_experimental_stack ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

resource "terraform_data" "prepare_generated_dirs" {
  count = var.enable_experimental_stack ? 1 : 0

  provisioner "local-exec" {
    command = "mkdir -p '${local.generated_objects_dir}'"
  }
}

resource "tls_private_key" "experiment" {
  count     = var.enable_experimental_stack ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_sensitive_file" "experiment_private_key" {
  count           = var.enable_experimental_stack ? 1 : 0
  filename        = "${local.generated_dir}/cloudfront-private-key.pem"
  content         = tls_private_key.experiment[0].private_key_pem
  file_permission = "0600"

  depends_on = [terraform_data.prepare_generated_dirs]
}

resource "aws_s3_bucket" "experiment" {
  count         = var.enable_experimental_stack ? 1 : 0
  bucket        = "${var.experiment_name_prefix}-${random_string.experiment_suffix[0].result}"
  force_destroy = true

  tags = merge(var.tags, {
    component = "benchmark-experiment-bucket"
  })
}

resource "aws_s3_bucket_public_access_block" "experiment" {
  count                   = var.enable_experimental_stack ? 1 : 0
  bucket                  = aws_s3_bucket.experiment[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "experiment" {
  count  = var.enable_experimental_stack ? 1 : 0
  bucket = aws_s3_bucket.experiment[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "terraform_data" "generate_object_files" {
  for_each = var.enable_experimental_stack ? local.experiment_object_defs : {}

  triggers_replace = [
    each.value.key,
    tostring(each.value.size_bytes)
  ]

  provisioner "local-exec" {
    command = "mkdir -p \"$(dirname '${local.experiment_object_file_paths[each.key]}')\" && dd if=/dev/zero of='${local.experiment_object_file_paths[each.key]}' bs=1 count=${each.value.size_bytes} status=none"
  }

  depends_on = [terraform_data.prepare_generated_dirs]
}

resource "aws_s3_object" "experiment_objects" {
  for_each = var.enable_experimental_stack ? local.experiment_object_defs : {}

  bucket       = aws_s3_bucket.experiment[0].id
  key          = each.value.key
  source       = local.experiment_object_file_paths[each.key]
  content_type = "application/octet-stream"

  depends_on = [terraform_data.generate_object_files]
}

resource "aws_cloudfront_origin_access_control" "experiment" {
  count                             = var.enable_experimental_stack ? 1 : 0
  name                              = "${var.experiment_name_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_public_key" "experiment" {
  count       = var.enable_experimental_stack ? 1 : 0
  name        = "${var.experiment_name_prefix}-public-key"
  encoded_key = tls_private_key.experiment[0].public_key_pem
  comment     = "Public key for CloudFront signed URL/cookie benchmark experiment"
}

resource "aws_cloudfront_key_group" "experiment" {
  count = var.enable_experimental_stack ? 1 : 0
  name  = "${var.experiment_name_prefix}-key-group"
  items = [aws_cloudfront_public_key.experiment[0].id]
}

resource "aws_cloudfront_cache_policy" "experiment" {
  count       = var.enable_experimental_stack ? 1 : 0
  name        = "${var.experiment_name_prefix}-cache-policy"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
  }
}

resource "aws_cloudfront_distribution" "experiment" {
  count               = var.enable_experimental_stack ? 1 : 0
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Private content benchmark experiment stack"
  price_class         = var.cloudfront_price_class
  wait_for_deployment = true

  origin {
    domain_name              = aws_s3_bucket.experiment[0].bucket_regional_domain_name
    origin_id                = "experiment-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.experiment[0].id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "experiment-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false
    trusted_key_groups     = [aws_cloudfront_key_group.experiment[0].id]
    cache_policy_id        = aws_cloudfront_cache_policy.experiment[0].id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.tags, {
    component = "benchmark-experiment-distribution"
  })
}

data "aws_iam_policy_document" "experiment_bucket_policy" {
  count = var.enable_experimental_stack ? 1 : 0

  statement {
    sid = "AllowCloudFrontReadAccess"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = [
      "${aws_s3_bucket.experiment[0].arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.experiment[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "experiment" {
  count  = var.enable_experimental_stack ? 1 : 0
  bucket = aws_s3_bucket.experiment[0].id
  policy = data.aws_iam_policy_document.experiment_bucket_policy[0].json
}
