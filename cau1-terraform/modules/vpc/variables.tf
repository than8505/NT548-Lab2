variable "name" {
  description = "Tiền tố đặt tên cho tài nguyên"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR của VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr phải là một CIDR hợp lệ."
  }
}

variable "azs" {
  description = "Danh sách Availability Zone sử dụng"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Danh sách CIDR cho Public Subnet"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "Cần ít nhất 1 Public Subnet (NAT Gateway đặt tại đây)."
  }
}

variable "private_subnet_cidrs" {
  description = "Danh sách CIDR cho Private Subnet"
  type        = list(string)
}

variable "enable_flow_logs" {
  description = "Bật VPC Flow Logs (khuyến nghị bởi Checkov CKV2_AWS_11)"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Số ngày lưu Flow Logs (Checkov CKV_AWS_338 yêu cầu >= 365)"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tag chung"
  type        = map(string)
  default     = {}
}
