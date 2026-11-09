variable "aws_region" {
  description = "AWS Region triển khai"
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Tên dự án (dùng làm tiền tố đặt tên)"
  type        = string
  default     = "nt548-lab2"
}

variable "environment" {
  description = "Tên môi trường"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR của VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Danh sách AZ. Để trống = tự lấy 2 AZ đầu tiên của Region"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR các Public Subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR các Private Subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "allowed_ssh_cidr" {
  description = "IP được phép SSH vào Public EC2 (vd: 1.2.3.4/32). Lấy IP: curl ifconfig.me"
  type        = string
}

variable "instance_type" {
  description = "Loại EC2 instance"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "Nội dung SSH public key (ssh-ed25519 ... / ssh-rsa ...). Để trống nếu dùng existing_key_name"
  type        = string
  default     = ""
}

variable "existing_key_name" {
  description = "Tên Key Pair có sẵn trên AWS (dùng khi ssh_public_key rỗng). null = không dùng key"
  type        = string
  default     = null
}

variable "enable_flow_logs" {
  description = "Bật VPC Flow Logs"
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Tag bổ sung"
  type        = map(string)
  default     = {}
}
