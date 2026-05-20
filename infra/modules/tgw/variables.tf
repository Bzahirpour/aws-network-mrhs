variable "name" {
  description = "TGW name"
  type        = string
}

variable "amazon_side_asn" {
  description = "BGP ASN for the TGW"
  type        = number
  default     = 64512
}

variable "route_table_names" {
  description = "Names of route tables to create (e.g. [\"spoke\",\"shared\",\"egress\"])"
  type        = list(string)
}

variable "default_route_table_association" {
  description = "Whether to use a default TGW association route table (always disable for segmented designs)"
  type        = string
  default     = "disable"
}

variable "default_route_table_propagation" {
  description = "Whether to use a default TGW propagation route table (always disable for segmented designs)"
  type        = string
  default     = "disable"
}

variable "tags" {
  description = "Tags merged onto all resources"
  type        = map(string)
  default     = {}
}
