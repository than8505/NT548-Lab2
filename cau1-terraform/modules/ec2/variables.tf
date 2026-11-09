variable "name" {
  description = "Tên (tag Name) của instance"
  type        = string
}

variable "ami_id" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "Loại instance"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet đặt instance"
  type        = string
}

variable "security_group_ids" {
  description = "Danh sách Security Group gắn vào instance"
  type        = list(string)
}

variable "key_name" {
  description = "Tên EC2 Key Pair (null = không dùng key, truy cập bằng SSM)"
  type        = string
  default     = null
}

variable "associate_public_ip" {
  description = "Gán Public IP cho instance hay không"
  type        = bool
  default     = false
}

variable "iam_instance_profile" {
  description = "Tên IAM instance profile"
  type        = string
}

variable "user_data" {
  description = "User data (tùy chọn)"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Dung lượng root volume (GiB)"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tag chung"
  type        = map(string)
  default     = {}
}
