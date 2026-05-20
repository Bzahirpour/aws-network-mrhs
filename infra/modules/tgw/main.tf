terraform {
  required_version = "~> 1.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_ec2_transit_gateway" "this" {
  description                     = var.name
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = var.default_route_table_association
  default_route_table_propagation = var.default_route_table_propagation

  tags = merge(var.tags, {
    Name   = var.name
    Module = "tgw"
  })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each           = toset(var.route_table_names)
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name   = "${var.name}-rt-${each.key}"
    Module = "tgw"
  })
}
