resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  count = var.allow_all_egress ? 1 : 0

  security_group_id = aws_security_group.this.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  count = var.allow_all_egress && var.allow_ipv6_egress ? 1 : 0

  security_group_id = aws_security_group.this.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}
