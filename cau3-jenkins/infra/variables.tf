variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Tiền tố đặt tên"
  type        = string
  default     = "nt548-lab2-cau3"
}

variable "admin_cidr" {
  description = "IP quản trị được phép truy cập SSH, Jenkins (8080), SonarQube (9000) và ứng dụng (80/443). Vd 1.2.3.4/32"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr phải là CIDR hợp lệ và không được là 0.0.0.0/0."
  }
}

variable "app_public" {
  description = "Mở ứng dụng (80/443 trên node k3s) cho toàn Internet thay vì chỉ admin_cidr"
  type        = bool
  default     = false
}

variable "lab_repo_url" {
  description = "URL HTTPS của repo GitHub chứa bài lab (public), vd https://github.com/nhom05/NT548-Lab2.git"
  type        = string
}

variable "lab_repo_branch" {
  description = "Branch Jenkins theo dõi"
  type        = string
  default     = "main"
}

variable "ssh_public_key" {
  description = "SSH public key để đăng nhập 2 máy (để trống nếu chỉ dùng SSM Session Manager)"
  type        = string
  default     = ""
}

variable "jenkins_instance_type" {
  description = "Máy chạy Jenkins + SonarQube + Docker build (khuyến nghị >= 16GB RAM)"
  type        = string
  default     = "t3.xlarge"
}

variable "k3s_instance_type" {
  description = "Máy chạy k3s (ứng dụng ~13 pod)"
  type        = string
  default     = "t3.large"
}

variable "vpc_cidr" {
  description = "CIDR VPC cho Câu 3"
  type        = string
  default     = "10.20.0.0/16"
}
