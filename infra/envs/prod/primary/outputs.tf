output "tgw_id" {
  description = "Transit Gateway ID"
  value       = module.tgw.tgw_id
}

output "tgw_route_table_ids" {
  description = "Map of TGW route table name to ID"
  value       = module.tgw.route_table_ids
}

output "egress_vpc_id" {
  description = "Egress VPC ID"
  value       = module.egress_vpc.vpc_id
}

output "spoke1_vpc_id" {
  description = "Spoke-1 VPC ID"
  value       = module.spoke1_vpc.vpc_id
}

output "egress_attachment_id" {
  description = "Egress TGW attachment ID"
  value       = module.egress_attachment.attachment_id
}

output "spoke1_attachment_id" {
  description = "Spoke-1 TGW attachment ID"
  value       = module.spoke1_attachment.attachment_id
}
