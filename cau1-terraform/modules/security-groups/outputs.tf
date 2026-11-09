output "public_sg_id" {
  description = "ID Security Group của Public EC2"
  value       = aws_security_group.public.id
}

output "private_sg_id" {
  description = "ID Security Group của Private EC2"
  value       = aws_security_group.private.id
}
