aws_region      = "ap-northeast-2"
instance_type   = "t3.medium"
ami_name_prefix = "kaboocam-post-dev-golden-ami"

# Optional network placement for packer builder instance.
# Keep empty to use default behavior.
vpc_id            = ""
subnet_id         = ""
security_group_id = ""

tags = {
  Project     = "kaboocam-post"
  Environment = "dev"
  ManagedBy   = "packer"
}

# Override only when using external Loki.
loki_url = "http://loki:3100/loki/api/v1/push"
