locals {
  env          = "prod"
  region       = "us-east-1"
  region_short = "use1"

  # ── prod us-east-1 CIDR plan (10.10.0.0/16 supernet) ──────────────────────
  # Same /20 role offsets as dev; only the /16 base differs.

  egress_cidr      = "10.10.0.0/20"
  egress_tgw_cidrs = ["10.10.10.0/28"] # tgw-a (1a)

  spoke1_cidr          = "10.10.32.0/20"
  spoke1_private_cidrs = ["10.10.32.0/24"] # private-a (1a)
  spoke1_tgw_cidrs     = ["10.10.42.0/28"] # tgw-a (1a)

  common_tags = {
    Project     = "multi-region-hub-spoke"
    Environment = local.env
    Region      = local.region
    ManagedBy   = "terraform"
    Owner       = "bzahirpour"
  }
}
