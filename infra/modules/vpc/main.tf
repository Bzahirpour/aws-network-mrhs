terraform {
  required_version = "~> 1.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_subnet_map = length(var.public_subnet_cidrs) == 0 ? {} : {
    for i, az in local.azs : az => var.public_subnet_cidrs[i]
  }

  private_subnet_map = length(var.private_subnet_cidrs) == 0 ? {} : {
    for i, az in local.azs : az => var.private_subnet_cidrs[i]
  }

  tgw_subnet_map = length(var.tgw_subnet_cidrs) == 0 ? {} : {
    for i, az in local.azs : az => var.tgw_subnet_cidrs[i]
  }

  create_public_rt = length(var.public_subnet_cidrs) > 0 && var.enable_internet_gateway
}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name   = "${var.name}-vpc"
    Module = "vpc"
  })
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name   = "${var.name}-default-sg"
    Module = "vpc"
  })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  count  = var.enable_internet_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name   = "${var.name}-igw"
    Module = "vpc"
  })
}

# ── Public subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  for_each          = local.public_subnet_map
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name   = "${var.name}-public-${each.key}"
    Module = "vpc"
  })
}

resource "aws_route_table" "public" {
  count  = local.create_public_rt ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name   = "${var.name}-rt-public"
    Module = "vpc"
  })
}

resource "aws_route" "public_igw" {
  count                  = local.create_public_rt ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each       = local.create_public_rt ? local.public_subnet_map : {}
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[0].id
}

# ── Private subnets ───────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  for_each          = local.private_subnet_map
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name   = "${var.name}-private-${each.key}"
    Module = "vpc"
  })
}

resource "aws_route_table" "private" {
  for_each = local.private_subnet_map
  vpc_id   = aws_vpc.this.id

  tags = merge(var.tags, {
    Name   = "${var.name}-rt-private-${each.key}"
    Module = "vpc"
  })
}

resource "aws_route_table_association" "private" {
  for_each       = local.private_subnet_map
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# ── TGW subnets ───────────────────────────────────────────────────────────────

resource "aws_subnet" "tgw" {
  for_each          = local.tgw_subnet_map
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name   = "${var.name}-tgw-${each.key}"
    Module = "vpc"
  })
}

resource "aws_route_table" "tgw" {
  for_each = local.tgw_subnet_map
  vpc_id   = aws_vpc.this.id

  tags = merge(var.tags, {
    Name   = "${var.name}-rt-tgw-${each.key}"
    Module = "vpc"
  })
}

resource "aws_route_table_association" "tgw" {
  for_each       = local.tgw_subnet_map
  subnet_id      = aws_subnet.tgw[each.key].id
  route_table_id = aws_route_table.tgw[each.key].id
}

# ── Regional NAT Gateway (D-007) ──────────────────────────────────────────────
# availability_mode = "regional" requires AWS provider >= 6.24 (added v6.24.0).
# One EIP per active AZ; AWS manages the IGW route automatically.

resource "aws_eip" "nat" {
  for_each = var.enable_nat_gateway ? toset(local.azs) : toset([])
  domain   = "vpc"

  tags = merge(var.tags, {
    Name   = "${var.name}-nat-eip-${each.key}"
    Module = "vpc"
  })
}

resource "aws_nat_gateway" "this" {
  count             = var.enable_nat_gateway ? 1 : 0
  vpc_id            = aws_vpc.this.id
  availability_mode = "regional"
  connectivity_type = "public"

  dynamic "availability_zone_address" {
    for_each = local.azs
    content {
      allocation_ids    = [aws_eip.nat[availability_zone_address.value].id]
      availability_zone = availability_zone_address.value
    }
  }

  tags = merge(var.tags, {
    Name   = "${var.name}-nat-gw"
    Module = "vpc"
  })

  depends_on = [aws_internet_gateway.this]
}

# ── VPC Flow Logs → CloudWatch ────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "${var.name}-flow-logs"
  retention_in_days = 7

  tags = merge(var.tags, {
    Name   = "${var.name}-flow-logs"
    Module = "vpc"
  })
}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json

  tags = merge(var.tags, {
    Name   = "${var.name}-flow-logs-role"
    Module = "vpc"
  })
}

data "aws_iam_policy_document" "flow_logs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.flow_logs.arn,
      "${aws_cloudwatch_log_group.flow_logs.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.name}-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_policy.json
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = merge(var.tags, {
    Name   = "${var.name}-flow-log"
    Module = "vpc"
  })
}
