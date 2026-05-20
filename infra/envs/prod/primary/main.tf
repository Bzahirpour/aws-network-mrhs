provider "aws" {
  region = local.region

  default_tags {
    tags = local.common_tags
  }
}

# ── Transit Gateway ───────────────────────────────────────────────────────────

module "tgw" {
  source            = "../../../modules/tgw"
  name              = "mrhs-${local.region_short}-tgw"
  route_table_names = ["spoke", "shared", "egress"]
  tags              = local.common_tags
}

# ── Egress VPC ────────────────────────────────────────────────────────────────

module "egress_vpc" {
  source                  = "../../../modules/vpc"
  name                    = "mrhs-${local.region_short}-egress"
  cidr                    = local.egress_cidr
  az_count                = 1
  tgw_subnet_cidrs        = local.egress_tgw_cidrs
  enable_nat_gateway      = true
  enable_internet_gateway = true
  tags                    = local.common_tags
}

# ── Spoke-1 VPC ───────────────────────────────────────────────────────────────

module "spoke1_vpc" {
  source               = "../../../modules/vpc"
  name                 = "mrhs-${local.region_short}-spoke1"
  cidr                 = local.spoke1_cidr
  az_count             = 1
  private_subnet_cidrs = local.spoke1_private_cidrs
  tgw_subnet_cidrs     = local.spoke1_tgw_cidrs
  tags                 = local.common_tags
}

# ── TGW Attachments ───────────────────────────────────────────────────────────

module "egress_attachment" {
  source                        = "../../../modules/tgw-attachment"
  name                          = "mrhs-${local.region_short}-egress-attach"
  transit_gateway_id            = module.tgw.tgw_id
  vpc_id                        = module.egress_vpc.vpc_id
  subnet_ids                    = module.egress_vpc.tgw_subnet_ids
  associate_with_route_table_id = module.tgw.route_table_ids["egress"]
  propagate_to_route_table_ids  = {}
  tags                          = local.common_tags
}

module "spoke1_attachment" {
  source                        = "../../../modules/tgw-attachment"
  name                          = "mrhs-${local.region_short}-spoke1-attach"
  transit_gateway_id            = module.tgw.tgw_id
  vpc_id                        = module.spoke1_vpc.vpc_id
  subnet_ids                    = module.spoke1_vpc.tgw_subnet_ids
  associate_with_route_table_id = module.tgw.route_table_ids["spoke"]
  propagate_to_route_table_ids  = { egress = module.tgw.route_table_ids["egress"] }
  tags                          = local.common_tags
}
