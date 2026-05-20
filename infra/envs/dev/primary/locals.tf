locals {
  env          = "dev"
  region       = "us-east-1"
  region_short = "use1"

  # ── dev us-east-1 CIDR plan (10.0.0.0/16 supernet) ────────────────────────
  # Subnet offsets are identical across all region/env combos — only the /16
  # base changes. Phase 1 activates az_count = 1 (us-east-1a only).

  egress_cidr      = "10.0.0.0/20"
  egress_tgw_cidrs = ["10.0.10.0/28"] # tgw-a (1a)

  spoke1_cidr          = "10.0.32.0/20"
  spoke1_private_cidrs = ["10.0.32.0/24"] # private-a (1a)
  spoke1_tgw_cidrs     = ["10.0.42.0/28"] # tgw-a (1a)

  common_tags = {
    Project     = "multi-region-hub-spoke"
    Environment = local.env
    Region      = local.region
    ManagedBy   = "terraform"
    Owner       = "bzahirpour"
  }
}
