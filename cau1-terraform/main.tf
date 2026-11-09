###############################################################################
# NT548 - Lab 2 - Câu 1: Triển khai hạ tầng Lab 1 bằng Terraform
#
#   Internet
#      │
#   [IGW]
#      │
#   ┌──┴──────────── VPC 10.0.0.0/16 ───────────────────────┐
#   │  Public Subnet (10.0.1.0/24)    Private Subnet (10.0.2.0/24)
#   │   ├─ Public EC2 (bastion) ──SSH──▶ Private EC2         │
#   │   └─ NAT Gateway ◀──────────────── 0.0.0.0/0           │
#   └────────────────────────────────────────────────────────┘
###############################################################################

locals {
  name = "${var.project}-${var.environment}"

  tags = merge(var.extra_tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Lab         = "NT548-Lab2-Cau1"
  })

  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 2)
}

data "aws_availability_zones" "available" {
  state = "available"
}

# AMI Amazon Linux 2023 mới nhất (lấy từ SSM Public Parameter)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ----------------------------------------------------------------------------
# 1. Mạng: VPC, Subnets, IGW, NAT, Route Tables
# ----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_flow_logs     = var.enable_flow_logs
  tags                 = local.tags
}

# ----------------------------------------------------------------------------
# 2. Security Groups
# ----------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security-groups"

  name             = local.name
  vpc_id           = module.vpc.vpc_id
  allowed_ssh_cidr = var.allowed_ssh_cidr
  tags             = local.tags
}

# ----------------------------------------------------------------------------
# 3. IAM role cho EC2 (cho phép quản lý qua SSM Session Manager)
# ----------------------------------------------------------------------------
resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = local.tags
}

# ----------------------------------------------------------------------------
# 4. Key Pair (tùy chọn) - dùng public key truyền vào
# ----------------------------------------------------------------------------
resource "aws_key_pair" "this" {
  count = var.ssh_public_key != "" ? 1 : 0

  key_name   = "${local.name}-key"
  public_key = var.ssh_public_key
  tags       = local.tags
}

locals {
  key_name = var.ssh_public_key != "" ? aws_key_pair.this[0].key_name : var.existing_key_name
}

# ----------------------------------------------------------------------------
# 5. EC2 Instances
# ----------------------------------------------------------------------------
module "public_ec2" {
  source = "./modules/ec2"

  name                 = "${local.name}-public-ec2"
  ami_id               = data.aws_ssm_parameter.al2023.value
  instance_type        = var.instance_type
  subnet_id            = module.vpc.public_subnet_ids[0]
  security_group_ids   = [module.security_groups.public_sg_id]
  key_name             = local.key_name
  associate_public_ip  = true
  iam_instance_profile = aws_iam_instance_profile.ec2.name
  tags                 = merge(local.tags, { Role = "bastion" })
}

module "private_ec2" {
  source = "./modules/ec2"

  name                 = "${local.name}-private-ec2"
  ami_id               = data.aws_ssm_parameter.al2023.value
  instance_type        = var.instance_type
  subnet_id            = module.vpc.private_subnet_ids[0]
  security_group_ids   = [module.security_groups.private_sg_id]
  key_name             = local.key_name
  associate_public_ip  = false
  iam_instance_profile = aws_iam_instance_profile.ec2.name
  tags                 = merge(local.tags, { Role = "private" })

  # Đảm bảo NAT đã sẵn sàng để private instance có Internet khi khởi động
  depends_on = [module.vpc]
}
