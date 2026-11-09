output "jenkins_url" {
  description = "Jenkins UI"
  value       = "http://${aws_instance.jenkins.public_ip}:8080/"
}

output "sonarqube_url" {
  description = "SonarQube UI"
  value       = "http://${aws_instance.jenkins.public_ip}:9000/"
}

output "app_url" {
  description = "Ứng dụng Aurapan (qua Traefik ingress của k3s, chứng chỉ self-signed)"
  value       = "https://${aws_instance.k3s.public_ip}/"
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "k3s_public_ip" {
  value = aws_instance.k3s.public_ip
}

output "k3s_private_ip" {
  value = aws_instance.k3s.private_ip
}

output "kubeconfig_bucket" {
  value = aws_s3_bucket.kubeconfig.bucket
}

output "ssh_commands" {
  value = {
    jenkins = "ssh ubuntu@${aws_instance.jenkins.public_ip}"
    k3s     = "ssh ubuntu@${aws_instance.k3s.public_ip}"
  }
}

output "ssm_commands" {
  description = "Đăng nhập không cần SSH key (cần AWS CLI + Session Manager plugin)"
  value = {
    jenkins = "aws ssm start-session --target ${aws_instance.jenkins.id} --region ${var.aws_region}"
    k3s     = "aws ssm start-session --target ${aws_instance.k3s.id} --region ${var.aws_region}"
  }
}
