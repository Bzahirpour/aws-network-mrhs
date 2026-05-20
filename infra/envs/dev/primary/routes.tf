# ── VPC-side routes ───────────────────────────────────────────────────────────

# Egress VPC TGW subnets: 0.0.0.0/0 → Regional NAT GW
# Traffic arriving from TGW exits toward the internet through the NAT GW.
resource "aws_route" "egress_tgw_to_nat" {
  for_each               = module.egress_vpc.tgw_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.egress_vpc.nat_gateway_ids[0]
}

# Spoke-1 private subnets: 0.0.0.0/0 → TGW
# All outbound traffic from workloads enters the TGW for centralized egress.
resource "aws_route" "spoke1_private_to_tgw" {
  for_each               = module.spoke1_vpc.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.tgw.tgw_id
  depends_on             = [module.spoke1_attachment]
}

# ── TGW route table routes ────────────────────────────────────────────────────

# rt-spoke: 0.0.0.0/0 → egress attachment
# All spoke traffic with no more-specific match goes to the egress VPC.
resource "aws_ec2_transit_gateway_route" "spoke_default_to_egress" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = module.egress_attachment.attachment_id
  transit_gateway_route_table_id = module.tgw.route_table_ids["spoke"]
}
