# Pinning the AWS provider version so this doesn't randomly break later
# if HashiCorp ships something incompatible in a newer release.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

# No access keys here on purpose - Terraform just picks up whatever's
# already configured via `aws configure` (~/.aws/credentials) on this
# machine, so nothing sensitive ever ends up in this file or in git.
provider "aws" {
  region = var.aws_region
}