resource "aws_security_group" "app" {
  name_prefix = "${local.name}-"
  description = "ExcaliDash host: HTTPS from Cloudflare, optional SSH"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "https_ipv4" {
  for_each = toset(var.cloudflare_ipv4_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Cloudflare IPv4"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https_ipv6" {
  for_each = toset(var.cloudflare_ipv6_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Cloudflare IPv6"
  cidr_ipv6         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_ipv4" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Operator SSH IPv4"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_ipv6" {
  for_each = toset(var.ssh_allowed_ipv6_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Operator SSH IPv6"
  cidr_ipv6         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
