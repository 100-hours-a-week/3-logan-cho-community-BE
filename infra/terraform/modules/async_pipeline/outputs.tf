output "queue_url" {
  value = aws_sqs_queue.main.url
}

output "queue_arn" {
  value = aws_sqs_queue.main.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.processor.function_name
}

output "dlq_url" {
  value = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}
