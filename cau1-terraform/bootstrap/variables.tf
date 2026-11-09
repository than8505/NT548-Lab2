variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Tiền tố đặt tên (phải trùng với biến project của thư mục gốc)"
  type        = string
  default     = "nt548-lab2"
}

variable "github_repo" {
  description = "Repo GitHub dạng <owner>/<repo>, ví dụ: nhom05/NT548-Lab2"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo phải có dạng owner/repo."
  }
}

variable "create_github_oidc_provider" {
  description = "Tạo GitHub OIDC provider. Đặt false nếu account đã có sẵn provider này"
  type        = bool
  default     = true
}

variable "force_destroy_state_bucket" {
  description = "Cho phép xóa state bucket kể cả khi còn object (dùng khi dọn lab)"
  type        = bool
  default     = false
}
