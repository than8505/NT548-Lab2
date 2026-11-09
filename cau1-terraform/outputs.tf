output "vpc_id" {
  description = "ID của VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = module.vpc.nat_gateway_id
}

output "nat_public_ip" {
  description = "Public IP của NAT Gateway (IP đi ra Internet của Private EC2)"
  value       = module.vpc.nat_public_ip
}

output "public_route_table_id" {
  description = "Public Route Table ID"
  value       = module.vpc.public_route_table_id
}

output "private_route_table_id" {
  description = "Private Route Table ID"
  value       = module.vpc.private_route_table_id
}

output "public_sg_id" {
  description = "Security Group của Public EC2"
  value       = module.security_groups.public_sg_id
}

output "private_sg_id" {
  description = "Security Group của Private EC2"
  value       = module.security_groups.private_sg_id
}

output "public_ec2_id" {
  description = "Instance ID của Public EC2"
  value       = module.public_ec2.instance_id
}

output "public_ec2_public_ip" {
  description = "Public IP của Public EC2"
  value       = module.public_ec2.public_ip
}

output "private_ec2_id" {
  description = "Instance ID của Private EC2"
  value       = module.private_ec2.instance_id
}

output "private_ec2_private_ip" {
  description = "Private IP của Private EC2"
  value       = module.private_ec2.private_ip
}

output "ssh_commands" {
  description = "Lệnh SSH mẫu để kiểm tra"
  value = {
    to_public_ec2           = "ssh -i <key.pem> ec2-user@${module.public_ec2.public_ip}"
    to_private_via_jumphost = "ssh -i <key.pem> -J ec2-user@${module.public_ec2.public_ip} ec2-user@${module.private_ec2.private_ip}"
  }
}
