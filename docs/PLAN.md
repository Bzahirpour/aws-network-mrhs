# Multi-Region Hub-and-Spoke Terraform Project

## Objective

Build a reusable Terraform project that provisions a multi-region AWS hub-and-spoke architecture using Transit Gateway, with route-domain isolation between spokes, centralized internet egress, centralized shared services (DNS + Interface VPC endpoints), and TGW peering between regions. The architecture demonstrates production patterns at portfolio scale and is the foundation for future enhancements (IPAM, inspection VPC, hybrid connectivity).

---

## Scope

### In Scope (v1)

- Two AWS regions: **us-east-1** (primary), **us-west-2** (secondary)
- One Transit Gateway per region with segmented route tables (spoke / shared-services / egress route domains)
- One **egress VPC** per region with NAT Gateway (single-AZ in v1 for cost; multi-AZ ready via variables)
- One **shared services VPC** per region hosting centralized Interface VPC endpoints
- Two **spoke VPCs** per region demonstrating route-domain isolation (cannot reach each other; can reach shared services and egress)
- Centralized DNS via Route 53 Private Hosted Zones, associated to spoke VPCs in-region
- TGW inter-region peering with static routes
- S3 remote state with native locking, GitHub Actions CI/CD via OIDC, hardened plan-JSON-aware pipeline with linting (fmt + tflint), security scanning (Trivy + Checkov + Claude security review), cost estimation (Infracost), and GitHub Environment approval gates on both dev and prod applies. See README.md 'CI/CD gate' section for full pipeline architecture.

### Out of Scope (v1)

- AWS IPAM (deferred to Phase 7 / v2 — see Decisions Log)
- AWS Cloud WAN
- Inspection VPC with Gateway Load Balancer / AWS Network Firewall
- Hybrid connectivity (Direct Connect, Site-to-Site VPN)
- IPv6
- Cross-account RAM sharing of TGW or PHZs (single-account demo)
- Application workloads beyond minimal test EC2 instances

---

## Architecture

See `docs/architecture-overview.svg` (high-level) and `docs/architecture-detail.svg` (TGW route tables, PHZ flow).

**Topology summary:**

- Each region: 1 TGW, 1 egress VPC, 1 shared services VPC, 2 spoke VPCs
- TGW route tables per region: `rt-spoke`, `rt-shared`, `rt-egress`
  - Spoke attachments **associate** to `rt-spoke`, **propagate** to `rt-shared` and `rt-egress`
  - Egress attachment **associates** to `rt-egress`, **propagates** to nothing (it's the default-route target, doesn't need to advertise)
  - Shared services attachment **associates** to `rt-shared`, **propagates** to `rt-spoke`
- Spokes get `0.0.0.0/0` → TGW → egress VPC → NAT → IGW
- Spokes get shared services CIDR → TGW → shared services VPC → endpoint ENIs
- Spoke-to-spoke traffic: dropped (no propagation between spokes within `rt-spoke`)
- Inter-region: TGW peering attachment, static routes in `rt-spoke` of each region for the remote region's spoke CIDRs

---

## CIDR Plan

**Strategy:** /16 per region, /20 per VPC role, /24 subnets within VPCs. Leaves ample room to add spokes without renumbering. Non-overlapping across regions for inter-region routing.

### Region allocations

| Env  | Region    | Supernet         |
|------|-----------|------------------|
| dev  | us-east-1 | `10.0.0.0/16`    |
| dev  | us-west-2 | `10.1.0.0/16`    |
| prod | us-east-1 | `10.10.0.0/16`   |
| prod | us-west-2 | `10.11.0.0/16`   |

Non-overlapping across both region **and** lifecycle so dev and prod can coexist (or eventually be peered for migration scenarios) without renumbering.

### VPC allocations (shown for dev us-east-1 — same /20 offsets within each region's /16)

| VPC               | CIDR             | Role                                            |
|-------------------|------------------|-------------------------------------------------|
| egress            | `10.0.0.0/20`    | Regional NAT GW + IGW (VPC-level), TGW subnets  |
| shared-services   | `10.0.16.0/20`   | Interface endpoint ENIs, TGW subnets            |
| spoke-1           | `10.0.32.0/20`   | Workload VPC                                    |
| spoke-2           | `10.0.48.0/20`   | Workload VPC                                    |
| *reserved (3-12)* | `10.0.64.0/20` … | Future spokes                                   |

The same offsets apply within `10.1.0.0/16` (dev us-west-2), `10.10.0.0/16` (prod us-east-1), and `10.11.0.0/16` (prod us-west-2). For example, the prod us-east-1 egress VPC is `10.10.0.0/20`, prod us-west-2 spoke-1 is `10.11.32.0/20`, and so on. Predictable scheme = easier to read route tables in the console.

### Subnet plan (within each VPC)

Each VPC uses **3 AZs available, 1 AZ active in v1**. Reserved subnets exist for AZ-b and AZ-c so multi-AZ enablement is just toggling a variable, not renumbering.

**Egress VPC** (`10.0.0.0/20` example):

With Regional NAT Gateway, no public subnet is required. The Regional NAT GW is a VPC-level resource with its own AWS-managed route to the IGW. Only TGW attachment subnets are needed.

| Subnet          | CIDR             | AZ      | Purpose                          |
|-----------------|------------------|---------|----------------------------------|
| tgw-a           | `10.0.10.0/28`   | 1a      | TGW attachment ENI               |
| tgw-b           | `10.0.10.16/28`  | 1b      | (reserved — auto-used if active) |
| tgw-c           | `10.0.10.32/28`  | 1c      | (reserved — auto-used if active) |

TGW attachment subnet RT: `0.0.0.0/0 → Regional NAT Gateway`. The Regional NAT GW has its own AWS-managed RT with a pre-configured route to the IGW; it expands across AZs automatically when ENIs appear in new AZs (up to ~60 min propagation per AZ).

**Shared services VPC** (`10.0.16.0/20`):

| Subnet          | CIDR             | AZ      | Purpose                  |
|-----------------|------------------|---------|--------------------------|
| private-a       | `10.0.16.0/24`   | 1a      | Interface endpoint ENIs  |
| private-b       | `10.0.17.0/24`   | 1b      | (reserved)               |
| private-c       | `10.0.18.0/24`   | 1c      | (reserved)               |
| tgw-a           | `10.0.26.0/28`   | 1a      | TGW attachment ENI       |
| tgw-b           | `10.0.26.16/28`  | 1b      | (reserved)               |
| tgw-c           | `10.0.26.32/28`  | 1c      | (reserved)               |

**Spoke VPC** (`10.0.32.0/20` for spoke-1):

| Subnet          | CIDR             | AZ      | Purpose                  |
|-----------------|------------------|---------|--------------------------|
| private-a       | `10.0.32.0/24`   | 1a      | Workloads                |
| private-b       | `10.0.33.0/24`   | 1b      | (reserved)               |
| private-c       | `10.0.34.0/24`   | 1c      | (reserved)               |
| tgw-a           | `10.0.42.0/28`   | 1a      | TGW attachment ENI       |
| tgw-b           | `10.0.42.16/28`  | 1b      | (reserved)               |
| tgw-c           | `10.0.42.32/28`  | 1c      | (reserved)               |

**TGW subnets get their own dedicated /28 per AZ** — AWS recommends this so attachment ENIs aren't co-mingled with workload subnets, which simplifies route table design.

---

## Module Structure

```
modules/
  vpc/                  # Generic VPC primitive
  tgw/                  # Transit Gateway + route tables (no attachments)
  tgw-attachment/       # Single VPC attachment + RT association + propagations
  tgw-peering/          # Inter-region TGW peering attachment + static routes
  endpoints-hub/        # Centralized Interface endpoints + PHZs (per region)
envs/
  dev/
    primary/            # us-east-1 composition (dev)
    secondary/          # us-west-2 composition (dev)
    global/             # Inter-region peering, cross-region PHZ associations (dev)
  prod/
    primary/            # us-east-1 composition (prod)
    secondary/          # us-west-2 composition (prod)
    global/             # Inter-region peering, cross-region PHZ associations (prod)
```

**Lifecycle × region two-axis layout.** Lifecycle is the outer boundary — different state files, different access controls, different approval gates per the template's CI/CD. Each leaf directory is independently planned and applied. The same modules compose both environments; only the variable values (CIDRs, AZ counts, multi-AZ toggles) differ.

**For v1 only `envs/dev/*` is actually deployed.** Prod is scaffolded with the same modules and a separate state but stays in code, not in AWS, until you specifically want to validate the prod path or capture README artifacts.

### Module Interface Contracts

#### `modules/vpc`
**Purpose:** Generic VPC primitive used for egress, shared services, and spoke roles.

| Input                     | Type           | Required | Description                                              |
|---------------------------|----------------|----------|----------------------------------------------------------|
| `name`                    | string         | yes      | VPC name, used in tag and resource names                 |
| `cidr`                    | string         | yes      | VPC CIDR (e.g. `10.0.0.0/20`)                            |
| `az_count`                | number         | no (1)   | Number of AZs to activate (1, 2, or 3)                   |
| `public_subnet_cidrs`     | list(string)   | no ([])  | Public subnet CIDRs (one per AZ). Empty = no public subs |
| `private_subnet_cidrs`    | list(string)   | no ([])  | Private subnet CIDRs                                     |
| `tgw_subnet_cidrs`        | list(string)   | no ([])  | Dedicated TGW attachment subnet CIDRs (/28 each)         |
| `enable_nat_gateway`      | bool           | no (false) | Provision NAT GW in first public subnet                |
| `enable_internet_gateway` | bool           | no (false) | Provision IGW                                          |
| `tags`                    | map(string)    | no ({})  | Tags merged onto all resources                           |

| Output                  | Description                                          |
|-------------------------|------------------------------------------------------|
| `vpc_id`                | VPC ID                                               |
| `vpc_cidr`              | Echoed CIDR for downstream consumers                 |
| `public_subnet_ids`     | List of public subnet IDs                            |
| `private_subnet_ids`    | List of private subnet IDs                           |
| `tgw_subnet_ids`        | List of TGW attachment subnet IDs                    |
| `nat_gateway_ids`       | List of NAT GW IDs (empty if not enabled)            |
| `public_route_table_id` | Route table for public subnets (if IGW enabled)      |
| `private_route_table_ids` | Map of AZ → private RT ID                          |

#### `modules/tgw`
**Purpose:** Transit Gateway + named route tables. Does **not** create attachments.

| Input                              | Type         | Required | Description                                |
|------------------------------------|--------------|----------|--------------------------------------------|
| `name`                             | string       | yes      | TGW name                                   |
| `amazon_side_asn`                  | number       | no (64512) | BGP ASN for TGW                          |
| `route_table_names`                | list(string) | yes      | Names of route tables to create (e.g. `["spoke","shared","egress"]`) |
| `default_route_table_association`  | string       | no (`"disable"`) | Always disable in segmented designs |
| `default_route_table_propagation`  | string       | no (`"disable"`) | Always disable in segmented designs |
| `tags`                             | map(string)  | no ({})  | Tags                                       |

| Output                  | Description                                          |
|-------------------------|------------------------------------------------------|
| `tgw_id`                | TGW ID                                               |
| `tgw_arn`               | TGW ARN                                              |
| `route_table_ids`       | Map of route table name → ID                         |

#### `modules/tgw-attachment`
**Purpose:** Attach one VPC to a TGW with explicit association and propagation control.

| Input                          | Type         | Required | Description                                  |
|--------------------------------|--------------|----------|----------------------------------------------|
| `name`                         | string       | yes      | Attachment name                              |
| `transit_gateway_id`           | string       | yes      | TGW ID                                       |
| `vpc_id`                       | string       | yes      | VPC to attach                                |
| `subnet_ids`                   | list(string) | yes      | TGW subnet IDs (one per AZ being activated)  |
| `associate_with_route_table_id`| string       | yes      | Which RT this attachment associates to       |
| `propagate_to_route_table_ids` | list(string) | no ([])  | RTs this attachment propagates routes into   |
| `tags`                         | map(string)  | no ({})  | Tags                                         |

| Output             | Description                                          |
|--------------------|------------------------------------------------------|
| `attachment_id`    | TGW attachment ID                                    |

#### `modules/tgw-peering`
**Purpose:** Create inter-region TGW peering attachment and static routes on both sides.

| Input                              | Type         | Required | Description                              |
|------------------------------------|--------------|----------|------------------------------------------|
| `name`                             | string       | yes      | Peering attachment name                  |
| `local_tgw_id`                     | string       | yes      | TGW in primary region                    |
| `peer_tgw_id`                      | string       | yes      | TGW in peer region                       |
| `peer_region`                      | string       | yes      | Peer region (e.g. `us-west-2`)           |
| `local_route_table_id`             | string       | yes      | RT in local TGW to install peer routes   |
| `peer_route_table_id`              | string       | yes      | RT in peer TGW to install local routes   |
| `local_cidrs`                      | list(string) | yes      | CIDRs in local region to advertise       |
| `peer_cidrs`                       | list(string) | yes      | CIDRs in peer region to install locally  |
| `tags`                             | map(string)  | no ({})  | Tags                                     |

**Note:** Uses provider aliases. Peer-side resources use a configured `aws.peer` provider.

| Output                  | Description                                          |
|-------------------------|------------------------------------------------------|
| `peering_attachment_id` | TGW peering attachment ID                            |

#### `modules/endpoints-hub`
**Purpose:** Centralized Interface VPC endpoints + Route 53 PHZs, associated with spoke VPCs.

| Input                  | Type           | Required | Description                                            |
|------------------------|----------------|----------|--------------------------------------------------------|
| `name_prefix`          | string         | yes      | Prefix for endpoint and PHZ names                      |
| `vpc_id`               | string         | yes      | Shared services VPC ID                                 |
| `subnet_ids`           | list(string)   | yes      | Private subnet IDs in shared services VPC (per AZ)     |
| `region`               | string         | yes      | AWS region (used in FQDN of PHZs)                      |
| `service_names`        | list(string)   | yes      | Short names (e.g. `["ssm","ssmmessages","ec2messages","kms"]`) |
| `endpoint_security_group_id` | string   | yes      | SG allowing 443 from spoke CIDRs                       |
| `spoke_vpc_ids`        | list(string)   | yes      | Spoke VPC IDs to associate PHZs with                   |
| `tags`                 | map(string)    | no ({})  | Tags                                                   |

| Output                  | Description                                          |
|-------------------------|------------------------------------------------------|
| `endpoint_ids`          | Map of service short name → VPC endpoint ID          |
| `phz_ids`               | Map of service short name → PHZ ID                   |

---

## Naming & Tagging

**Resource naming:** `<project>-<region>-<role>-<resource>`
Examples: `mrhs-use1-egress-vpc`, `mrhs-usw2-spoke1-tgw-attach`, `mrhs-use1-tgw-rt-spoke`

**Region shortcodes:** `use1` (us-east-1), `usw2` (us-west-2)

**Required tags on every resource:**

| Tag           | Value                                            |
|---------------|--------------------------------------------------|
| `Project`     | `multi-region-hub-spoke`                         |
| `Environment` | `dev` or `prod` (from env)                       |
| `Region`      | `us-east-1` or `us-west-2`                       |
| `Module`      | Module name (e.g. `vpc`, `tgw`, `endpoints-hub`) |
| `ManagedBy`   | `terraform`                                      |
| `Owner`      | `bzahirpour`                                    |

---

## Build Phases

Each phase ends with `terraform destroy` before the next session unless actively iterating. Phase acceptance is binary: the validation command either passes or it doesn't.

### Phase 1 — Single region, single spoke, egress only

**Build:**
- `modules/vpc` (generic primitive)
- `modules/tgw` with 3 route tables (`spoke`, `shared`, `egress`)
- `modules/tgw-attachment`
- `envs/dev/primary` composing: 1 TGW, 1 egress VPC (Regional NAT GW + IGW, TGW attachment subnet in 1a), 1 spoke VPC
- Default route in spoke private RT → TGW
- `0.0.0.0/0` in `rt-spoke` → egress attachment
- Egress VPC TGW subnet RT: `0.0.0.0/0` → Regional NAT GW
- Regional NAT GW's AWS-managed RT: return routes for spoke CIDRs → TGW attachment

**Validation:**
- Launch `t4g.nano` in spoke private subnet via SSM (no SSH)
- `curl https://aws.amazon.com` succeeds
- VPC flow logs show egress through Regional NAT GW public IP
- ✅ **Done when:** outbound HTTPS works from the spoke, traceroute shows TGW path

### Phase 2 — Second spoke + route-domain isolation

**Build:**
- Add `spoke-2` VPC + TGW attachment in `envs/dev/primary`
- Both spokes associate to `rt-spoke`, propagate to `rt-egress`
- Spokes do **not** propagate to `rt-spoke` (no spoke-to-spoke)

**Validation:**
- EC2 in spoke-1 cannot ping/SSM EC2 in spoke-2 (timeout)
- EC2 in spoke-1 and spoke-2 can both `curl` external
- ✅ **Done when:** spoke isolation enforced, egress still works for both

### Phase 3 — Shared services VPC + centralized SSM endpoint + PHZ

**Build:**
- `modules/endpoints-hub`
- Shared services VPC + TGW attachment, associate to `rt-shared`, propagate to `rt-spoke`
- Centralized SSM endpoints (ssm, ssmmessages, ec2messages) with Private DNS **disabled**
- PHZs for `ssm.us-east-1.amazonaws.com` (etc.) with ALIAS to endpoint regional DNS
- PHZ associations to both spoke VPCs
- Remove SSM/messages endpoints from spoke VPCs if previously local

**Validation:**
- EC2 in spoke connects to SSM via Session Manager (Connection type: shared services endpoint ENI)
- VPC flow logs in spoke show traffic to shared services CIDR, **not** to NAT
- `dig ssm.us-east-1.amazonaws.com` from EC2 returns shared services endpoint private IPs
- ✅ **Done when:** SSM works without public IPs or NAT path; DNS resolves to centralized endpoints

### Phase 4 — Replicate to second region (no peering)

**Build:**
- `envs/dev/secondary` mirroring `envs/dev/primary` with `10.1.x.x` CIDRs
- Same module versions, region-specific provider config
- Separate state key

**Validation:**
- Both regions work independently (re-run Phase 1-3 validation in us-west-2)
- ✅ **Done when:** us-west-2 demo passes all prior phase validations standalone

### Phase 5 — TGW peering + inter-region routes

**Build:**
- `modules/tgw-peering` with provider aliases
- `envs/dev/global` composes the peering attachment + static routes
- Static routes: us-east-1 `rt-spoke` gets `10.1.0.0/16` → peering attachment, mirror on us-west-2
- Inter-region PHZ associations only where genuinely needed (avoid by default)

**Validation:**
- EC2 in `use1-spoke-1` can SSM-connect or ping EC2 in `usw2-spoke-1`
- Route-domain isolation still holds (spoke-to-spoke within a region still blocked)
- ✅ **Done when:** inter-region spoke connectivity works, intra-region isolation preserved

### Phase 6 — README + diagram polish

**Build:**
- README walks the diagram, links module docs, shows sample `apply` output
- Cost summary section (referencing actual `aws ce` data after a session)
- `examples/` directory with a minimal usage snippet per module
- Module-level READMEs with terraform-docs auto-generated input/output tables

**Validation:**
- A reader who has never seen the repo can stand it up in one session by following the README
- ✅ **Done when:** README test passes (hand to a peer; they succeed without questions)

### Phase 7 (v2) — AWS IPAM migration

**Build (deferred):**
- IPAM with hierarchical pools: top-level → region pools → environment pools
- Migrate VPCs to allocate from IPAM pools via `ipv4_ipam_pool_id`
- Document migration approach (likely a rebuild given CIDR is immutable on existing VPCs)
- Decisions log entry capturing what IPAM bought you over hardcoded plan

---

## Decisions Log

### D-001: Hardcoded CIDR plan in `locals.tf` for v1, not AWS IPAM
**Date:** Project start
**Context:** Need IP address management strategy for 2 regions × ~4 VPCs.
**Decision:** Use a structured CIDR plan defined in `locals.tf` per env. Defer IPAM to Phase 7.
**Rationale:** IPAM Advanced tier is required for cross-region scenarios and adds operational complexity that obscures the routing fundamentals the project is meant to demonstrate. Hardcoded plan is sufficient for the project size, code-reviewable, and easier to reason about during phase validation. Migration to IPAM in v2 is itself a portfolio-worthy story showing evolution of thinking.
**Revisit if:** Adding 3+ regions, multi-account scenarios, or if address overlap becomes a real risk.

### D-002: Single-AZ default, multi-AZ ready via variable
**Date:** Project start
**Context:** Endpoint hourly cost scales per AZ. With Regional NAT Gateway (see D-007), NAT multi-AZ is automatic and free, so the multi-AZ trade-off is mostly about Interface endpoints.
**Decision:** Default `az_count = 1` in v1. Subnets pre-planned for 3 AZs so enabling multi-AZ is a variable change, not a renumbering.
**Rationale:** Interface endpoint cost during build phase ($0.01/hr per AZ per endpoint). Architecture supports multi-AZ; toggling for HA validation is a one-line change. Regional NAT GW will auto-expand to additional AZs as ENIs appear there.

### D-003: TGW peering, not Cloud WAN
**Date:** Project start
**Context:** Cloud WAN is more elegant at 3+ regions but pricier at this scale.
**Decision:** TGW peering for v1.
**Rationale:** Two regions, simpler cost model, more transferable knowledge (most production environments still run TGW). Cloud WAN is a valid future-state discussion.

### D-004: NAT in egress VPC, not shared services VPC
**Date:** Project start
**Context:** Egress and shared services could be combined to reduce TGW attachments and cost.
**Decision:** Keep them separate.
**Rationale:** Different blast radii, different change cadences, different security profiles. Combining them is a real-world optimization but architecturally muddier — the project is meant to show the canonical pattern.

### D-005: Single AWS account
**Date:** Project start
**Context:** Real production multi-region designs are usually multi-account (org-wide RAM sharing of TGW).
**Decision:** Single account for v1.
**Rationale:** Reduces setup friction without sacrificing the architectural lesson. Cross-account RAM is a v2 enhancement.

### D-007: Use Regional NAT Gateway, not zonal
**Date:** Architecture revision
**Context:** AWS introduced Regional NAT Gateway with automatic multi-AZ expansion. Standalone resource with its own AWS-managed route table, pre-configured route to IGW, no public subnet required.
**Decision:** Use Regional NAT Gateway in `regional` availability mode in each region's egress VPC.
**Rationale:**
- **No public subnet required** — eliminates risk of misplacing private resources in a subnet with `0.0.0.0/0 → IGW`
- **Single NAT ID** across all AZs — one route entry, simpler IaC
- **Automatic AZ expansion** — multi-AZ HA without managing N NAT gateways and N route tables
- **Higher capacity** — 32 IPs per AZ vs 8 for zonal, ~55K connections per IP per destination 5-tuple

The remaining trade-off (no private NAT support) doesn't apply since we're doing internet egress, not overlapping-CIDR NAT.
**Note:** Up to ~60-min propagation when expanding to a new AZ. Plan workload launches accordingly.

### D-008: Inspection VPC will be a separate VPC, not combined with egress
**Date:** Architecture revision (forward-looking)
**Status:** Out of scope v1; planned for v2 / Phase 8+.
**Decision:** When inspection VPC is added, it will be its own VPC with its own TGW attachment, distinct from the egress VPC.
**Traffic flow (v2):** `Spoke → TGW → Inspection VPC (GWLB → firewall → GWLB) → TGW → Egress VPC → Regional NAT → IGW → Internet`
**Rationale:**
- Different blast radii — firewall rule failure shouldn't take down egress
- Different change cadences — inspection is high-churn (rules, target groups, appliance fleets), egress is essentially static
- Cleaner ownership boundary in real orgs (security vs network team), aligns to RAM-sharing patterns when multi-account
- Inspection has its own routing complexity (GWLB endpoints, appliance route tables, return-path symmetry) that warrants its own VPC and visual treatment
- Combined is valid for very small environments or AWS Network Firewall transit-VPC mode; doesn't fit a portfolio-scale canonical pattern.

### D-009: Migrated from inherited template pipeline to hardened plan-JSON-aware pipeline
**Date:** 2026-05-22
**Context:** Inherited pipeline scanned raw HCL with tfsec (now deprecated, merged into Trivy) and applied with `-auto-approve`. Insufficient security posture for portfolio purposes.
**Decision:** Replaced with `pr-checks.yml` + `apply.yml`. Scanners (Trivy, Checkov) consume `terraform plan` JSON via `--framework terraform_plan`, not raw HCL. Adds Claude security review action in independent comment lane. Adds Infracost cost estimate. All third-party actions SHA-pinned with Dependabot auto-updates. Both dev and prod applies gated via GitHub Environment protection rules with required reviewers. `tfplan` saved as artifact between plan and apply jobs; applied via `terraform apply tfplan` with no `-auto-approve` flag (saved plans skip the prompt automatically).
**Rationale:**
- Plan-JSON scanning resolves variables, modules, and data sources before evaluation, eliminating a class of false negatives that HCL-only scanning produces
- Saved-plan apply ensures the plan reviewed at PR time is the plan applied at merge time (modulo state drift)
- Environment gates on both dev and prod prevent the self-merge fast-path the inherited pipeline allowed
- Multiple scanners (Trivy + Checkov + Claude) provide independent coverage: deterministic rule-based + semantic
- SHA-pinning closes supply-chain risk from re-tagged actions
**Revisit if:** Build minutes become a binding constraint, or scanner false-positive volume outpaces remediation capacity.

---

## State Backend

- **Bucket:** `mrhs-tfstate-453624448159` (create via bootstrap before first apply)
- **Region:** `us-east-1` (state always lives in one region regardless of resource region)
- **Locking:** S3 native locking via `use_lockfile = true` (Terraform 1.10+, no DynamoDB)
- **State keys:**
  - `envs/dev/primary/terraform.tfstate`
  - `envs/dev/secondary/terraform.tfstate`
  - `envs/dev/global/terraform.tfstate`
  - `envs/prod/primary/terraform.tfstate`
  - `envs/prod/secondary/terraform.tfstate`
  - `envs/prod/global/terraform.tfstate`
- **Versioning:** enabled on bucket
- **Encryption:** SSE-S3 (or KMS if you want to demo BYOK)

Provider versions pinned in `versions.tf`:
- `terraform ~> 1.14`
- `hashicorp/aws ~> 6.0`

---

## Cost Management

### Build-phase ceiling
- **Target:** under $25 per teardown cycle
- **Hard ceiling:** AWS Budget alert at **$50** in the account, email + SNS

### Cost-saving rules during build
- `terraform destroy` at end of every working session unless mid-debug
- Single-AZ default
- `t4g.nano` for test instances (~$0.0042/hr) — sufficient for SSM, curl, ping
- Skip Interface endpoints in Phases 1-2; add them in Phase 3 when actually testing the pattern
- Do not leave EC2 running between sessions (`aws ec2 stop-instances` if not destroying)

### Expected per-hour cost when fully deployed (both regions, Phase 5+)
| Component                                   | Hourly  |
|---------------------------------------------|---------|
| 8× TGW attachments (4 per region)           | $0.40   |
| 2× TGW peering attachments                  | $0.10   |
| 2× Regional NAT Gateway                     | TBD¹    |
| 6× Interface endpoints (3 per region, 1 AZ) | $0.06   |
| 2× t4g.nano                                 | $0.01   |
| **Total (excl. Regional NAT GW)**           | **~$0.57/hr + NAT** |

¹ Regional NAT Gateway pricing is per VPC + per-GB processed; verify on the VPC pricing page before first apply since the rate may differ from zonal NAT GW.

24h ≈ $14 + NAT. 1 month if forgotten ≈ $410 + NAT. Stay disciplined with `terraform destroy`.

---

## Resolved Pre-Build Decisions

- [x] **VPC flow logs in v1:** yes. CloudWatch Logs, 7-day retention, one log group per VPC (`<vpc-name>-flow-logs`). Valuable for validation evidence in README.
- [x] **Test EC2 placement:** out-of-band. Spin a `t4g.nano` per session for validation, tear down with env. Modules stay pure infra.
- [x] **Phase 3 Interface endpoints:** `ssm`, `ssmmessages`, `ec2messages` only. Minimum to validate the centralized endpoint + PHZ pattern. Add `kms`, `logs`, etc. as future iteration if expanding the demo.
