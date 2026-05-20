variable "name" {
  description = "VPC name, used in tag and resource names"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR (e.g. 10.0.0.0/20)"
  type        = string
}

variable "az_count" {
  description = "Number of AZs to activate (1, 2, or 3)"
  type        = number
  default     = 1
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ). Empty = no public subnets."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = []
}

variable "tgw_subnet_cidrs" {
  description = "Dedicated TGW attachment subnet CIDRs (/28 each, one per AZ)"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Provision a Regional NAT Gateway (availability_mode = regional)"
  type        = bool
  default     = false
}

variable "enable_internet_gateway" {
  description = "Provision an Internet Gateway"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags merged onto all resources"
  type        = map(string)
  default     = {}
}
