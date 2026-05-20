output "tgw_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "tgw_arn" {
  description = "Transit Gateway ARN"
  value       = aws_ec2_transit_gateway.this.arn
}

output "route_table_ids" {
  description = "Map of route table name to ID"
  value       = { for name, rt in aws_ec2_transit_gateway_route_table.this : name => rt.id }
}
