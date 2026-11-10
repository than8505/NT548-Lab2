###############################################################################
# Module Security Groups
#   - Public SG : chỉ cho phép SSH (22) từ IP được chỉ định (allowed_ssh_cidr)
#   - Private SG: chỉ cho phép SSH (22) từ các instance thuộc Public SG
###############################################################################

resource "aws_security_group" "public" {
  #checkov:skip=CKV2_AWS_5:SG duoc gan vao EC2 qua bien module (vpc_security_group_ids), Checkov khong lan theo duoc qua module
  name        = "${var.name}-public-ec2-sg"
  description = "Public EC2 (bastion): SSH chi tu IP duoc chi dinh"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-public-ec2-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_ssh" {
  security_group_id = aws_security_group.public.id
  description       = "SSH tu IP quan tri"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.allowed_ssh_cidr

  tags = merge(var.tags, { Name = "public-ssh-from-admin" })
}

resource "aws_vpc_security_group_egress_rule" "public_all" {
  #checkov:skip=CKV_AWS_382:Bastion can ra Internet de cap nhat goi va SSH sang Private EC2
  security_group_id = aws_security_group.public.id
  description       = "Cho phep toan bo traffic di ra"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "private" {
  #checkov:skip=CKV2_AWS_5:SG duoc gan vao EC2 qua bien module (vpc_security_group_ids), Checkov khong lan theo duoc qua module
  name        = "${var.name}-private-ec2-sg"
  description = "Private EC2: SSH chi tu Public EC2 (bastion)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-private-ec2-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "private_ssh_from_public" {
  #checkov:skip=CKV_AWS_24:Nguon la Security Group cua bastion (referenced_security_group_id), khong phai 0.0.0.0/0
  security_group_id            = aws_security_group.private.id
  description                  = "SSH tu Public EC2 (bastion)"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.public.id

  tags = merge(var.tags, { Name = "private-ssh-from-bastion" })
}

resource "aws_vpc_security_group_egress_rule" "private_all" {
  #checkov:skip=CKV_AWS_382:Private EC2 ra Internet qua NAT Gateway (yeu cau cua Lab 1)
  security_group_id = aws_security_group.private.id
  description       = "Cho phep traffic di ra (qua NAT Gateway)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
