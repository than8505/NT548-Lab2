###############################################################################
# NT548 Lab 2 - Câu 3: Hạ tầng cho Jenkins + SonarQube và cụm k3s trên EC2
#
#   [Admin IP] ──8080/9000/22──▶ Jenkins EC2 (Docker: Jenkins, SonarQube, Postgres)
#        │                            │  docker build/push ──▶ Docker Hub
#        │                            │  kubectl (6443) / smoke test (443)
#        └──────80/443/22──────▶ k3s EC2 (Traefik ingress + ứng dụng Aurapan)
#
#   Kubeconfig (ServiceAccount jenkins-deployer) được k3s đẩy lên S3 (mã hóa),
#   máy Jenkins tải về -> không cần copy tay, không lưu trong Terraform state.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ----------------------------------------------------------------------------
# Network (1 public subnet là đủ cho môi trường CI/CD của lab)
# ----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ----------------------------------------------------------------------------
# Security Groups
# ----------------------------------------------------------------------------
resource "aws_security_group" "jenkins" {
  name        = "${var.project}-jenkins-sg"
  description = "Jenkins + SonarQube"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH tu admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "Jenkins UI tu admin"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "SonarQube UI tu admin"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    description = "Ra Internet (GitHub, Docker Hub, npm, k3s)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project}-jenkins-sg" }
}

resource "aws_security_group" "k3s" {
  name        = "${var.project}-k3s-sg"
  description = "k3s node"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH tu admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description     = "Kubernetes API tu Jenkins"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }
  ingress {
    description = "Kubernetes API tu admin (kubectl tu may ca nhan)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description     = "HTTPS tu Jenkins (smoke test)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }
  ingress {
    description = "HTTP ung dung"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.app_public ? "0.0.0.0/0" : var.admin_cidr]
  }
  ingress {
    description = "HTTPS ung dung"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.app_public ? "0.0.0.0/0" : var.admin_cidr]
  }
  egress {
    description = "Ra Internet (pull image)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project}-k3s-sg" }
}

# ----------------------------------------------------------------------------
# S3 bucket trung chuyển kubeconfig (private, mã hóa, chỉ 2 role truy cập)
# ----------------------------------------------------------------------------
resource "aws_s3_bucket" "kubeconfig" {
  bucket        = "${var.project}-kubeconfig-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "kubeconfig" {
  bucket                  = aws_s3_bucket.kubeconfig.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kubeconfig" {
  bucket = aws_s3_bucket.kubeconfig.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ----------------------------------------------------------------------------
# IAM: mỗi máy 1 role (SSM Session Manager + quyền S3 tối thiểu)
# ----------------------------------------------------------------------------
locals {
  ec2_assume = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "k3s" {
  name               = "${var.project}-k3s-role"
  assume_role_policy = local.ec2_assume
}

resource "aws_iam_role_policy" "k3s_put_kubeconfig" {
  name = "put-kubeconfig"
  role = aws_iam_role.k3s.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.kubeconfig.arn}/*"
    }]
  })
}

resource "aws_iam_role" "jenkins" {
  name               = "${var.project}-jenkins-role"
  assume_role_policy = local.ec2_assume
}

resource "aws_iam_role_policy" "jenkins_get_kubeconfig" {
  name = "get-kubeconfig"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.kubeconfig.arn}/jenkins/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = { k3s = aws_iam_role.k3s.name, jenkins = aws_iam_role.jenkins.name }
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k3s" {
  name = "${var.project}-k3s-profile"
  role = aws_iam_role.k3s.name
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_key_pair" "this" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.project}-key"
  public_key = var.ssh_public_key
}

# ----------------------------------------------------------------------------
# EC2: k3s node
# ----------------------------------------------------------------------------
resource "aws_instance" "k3s" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.k3s_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s.name
  key_name               = var.ssh_public_key != "" ? aws_key_pair.this[0].key_name : null

  user_data = templatefile("${path.module}/user-data/k3s.sh", {
    kubeconfig_bucket = aws_s3_bucket.kubeconfig.bucket
    aws_region        = var.aws_region
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = { Name = "${var.project}-k3s" }
}

# ----------------------------------------------------------------------------
# EC2: Jenkins + SonarQube
# ----------------------------------------------------------------------------
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.jenkins_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  key_name               = var.ssh_public_key != "" ? aws_key_pair.this[0].key_name : null

  user_data = templatefile("${path.module}/user-data/jenkins.sh", {
    kubeconfig_bucket = aws_s3_bucket.kubeconfig.bucket
    aws_region        = var.aws_region
    k3s_private_ip    = aws_instance.k3s.private_ip
    lab_repo_url      = var.lab_repo_url
    lab_repo_branch   = var.lab_repo_branch
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  tags = { Name = "${var.project}-jenkins" }
}
