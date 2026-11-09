variable "name" {
  description = "Tiền tố đặt tên"
  type        = string
}

variable "vpc_id" {
  description = "ID của VPC chứa Security Group"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR được phép SSH vào Public EC2, ví dụ 203.0.113.10/32"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr phải là CIDR hợp lệ và KHÔNG được là 0.0.0.0/0."
  }
}

variable "tags" {
  description = "Tag chung"
  type        = map(string)
  default     = {}
}
