###############################################################################
# Module EC2: một EC2 instance đã được hardening theo khuyến nghị Checkov
#   - IMDSv2 bắt buộc (CKV_AWS_79)
#   - Root volume mã hóa (CKV_AWS_8)
#   - Detailed monitoring (CKV_AWS_126), EBS optimized (CKV_AWS_135)
#   - Gắn IAM instance profile (CKV2_AWS_41)
###############################################################################

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_88:Public EC2 (bastion) can Public IP theo yeu cau Lab 1; Private EC2 dat false
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = var.key_name
  associate_public_ip_address = var.associate_public_ip
  iam_instance_profile        = var.iam_instance_profile
  user_data                   = var.user_data

  monitoring    = true
  ebs_optimized = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags        = merge(var.tags, { Name = var.name })
  volume_tags = merge(var.tags, { Name = "${var.name}-root" })
}
