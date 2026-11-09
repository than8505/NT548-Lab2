output "instance_id" {
  description = "ID của instance"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public IP (rỗng nếu là private instance)"
  value       = aws_instance.this.public_ip
}
