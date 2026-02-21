locals {
  public_subnet_map = {
    for idx, subnet_id in var.public_subnet_ids : tostring(idx) => subnet_id
  }

  private_route_table_map = {
    for idx, route_table_id in var.private_route_table_ids : tostring(idx) => route_table_id
  }
}

resource "aws_eip" "this" {
  for_each = local.public_subnet_map

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = local.public_subnet_map

  allocation_id = aws_eip.this[each.key].id
  subnet_id     = each.value

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.key}"
  })
}

resource "aws_route" "private_default" {
  for_each = local.private_route_table_map

  route_table_id         = each.value
  destination_cidr_block = var.private_default_route_cidr
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}
