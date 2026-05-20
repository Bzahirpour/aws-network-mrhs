output "attachment_id" {
  description = "TGW VPC attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}
