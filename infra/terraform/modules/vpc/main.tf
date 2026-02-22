data "aws_region" "current" {}

locals {
  public_subnet_map  = { for idx, az in var.availability_zones : az => var.public_subnet_cidrs[idx] }
  private_subnet_map = { for idx, az in var.availability_zones : az => var.private_subnet_cidrs[idx] }

  ssm_endpoint_services = toset([
    "ssm",
    "ec2messages",
    "ssmmessages"
  ])
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnet_map

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt-${each.key}"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_security_group" "ssm_endpoint" {
  count = var.enable_ssm_vpc_endpoints ? 1 : 0

  name        = "${var.name}-ssm-vpce-sg"
  description = "Security group for SSM interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-ssm-vpce-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssm_endpoint_https" {
  count = var.enable_ssm_vpc_endpoints ? 1 : 0

  security_group_id = aws_security_group.ssm_endpoint[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "ssm_endpoint_all" {
  count = var.enable_ssm_vpc_endpoints ? 1 : 0

  security_group_id = aws_security_group.ssm_endpoint[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_endpoint" "ssm_interface" {
  for_each = var.enable_ssm_vpc_endpoints ? local.ssm_endpoint_services : toset([])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for az in var.availability_zones : aws_subnet.private[az].id]
  security_group_ids  = [aws_security_group.ssm_endpoint[0].id]

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value}-vpce"
  })
}
