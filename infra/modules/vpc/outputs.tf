output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "tgw_subnet_ids" {
  description = "List of TGW attachment subnet IDs"
  value       = [for s in aws_subnet.tgw : s.id]
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (empty if not enabled)"
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "Route table ID for public subnets (null if IGW not enabled or no public subnets)"
  value       = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "private_route_table_ids" {
  description = "Map of AZ name to private route table ID"
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "tgw_route_table_ids" {
  description = "Map of AZ name to TGW subnet route table ID"
  value       = { for az, rt in aws_route_table.tgw : az => rt.id }
}

output "nat_gateway_route_table_id" {
  description = "Route table ID auto-created by AWS for the Regional NAT Gateway (null if NAT GW disabled)"
  value       = length(aws_nat_gateway.this) > 0 ? aws_nat_gateway.this[0].route_table_id : null
}
