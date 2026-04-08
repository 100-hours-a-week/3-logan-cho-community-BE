locals {
  lambda_package_path = var.lambda_package_path != null ? var.lambda_package_path : "${path.module}/placeholder.zip"
}

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                       = "${var.name_prefix}-image-dlq"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds

  tags = merge(var.tags, { Name = "${var.name_prefix}-image-dlq" })
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-image-main"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds

  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = 5
  }) : null

  tags = merge(var.tags, { Name = "${var.name_prefix}-image-main" })
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_inline" {
  name = "${var.name_prefix}-lambda-inline"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [aws_sqs_queue.main.arn]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-image-processor"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "processor" {
  filename                       = local.lambda_package_path
  function_name                  = "${var.name_prefix}-image-processor"
  role                           = aws_iam_role.lambda.arn
  handler                        = var.lambda_handler
  runtime                        = var.lambda_runtime
  memory_size                    = var.lambda_memory_size
  timeout                        = var.lambda_timeout
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  source_code_hash               = filebase64sha256(local.lambda_package_path)

  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 && length(var.lambda_security_group_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }

  environment {
    variables = merge(
      {
        SQS_QUEUE_URL = aws_sqs_queue.main.url
      },
      var.lambda_environment
    )
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = merge(var.tags, { Name = "${var.name_prefix}-image-processor" })
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = var.lambda_batch_size
  enabled          = true
}
