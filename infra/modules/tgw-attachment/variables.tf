variable "name" {
  description = "Attachment name"
  type        = string
}

variable "transit_gateway_id" {
  description = "TGW ID to attach to"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to attach"
  type        = string
}

variable "subnet_ids" {
  description = "TGW attachment subnet IDs (one per active AZ)"
  type        = list(string)
}

variable "associate_with_route_table_id" {
  description = "TGW route table ID this attachment associates with"
  type        = string
}

variable "propagate_to_route_table_ids" {
  description = "Map of logical name to TGW route table ID for propagation targets (static keys required for for_each)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags merged onto all resources"
  type        = map(string)
  default     = {}
}
