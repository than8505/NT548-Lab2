terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state trên S3, khóa state bằng S3 native lockfile (Terraform >= 1.10).
  # Cấu hình bucket/key/region được truyền lúc init:
  #   terraform init -backend-config=backend.hcl
  # (GitHub Actions truyền qua -backend-config trong composite action)
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
