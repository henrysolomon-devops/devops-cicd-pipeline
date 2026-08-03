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

# No access keys hardcoded here on purpose - Terraform just picks up
# whatever credentials are already available in its environment. When
# this runs inside infra.yml on a GitHub-hosted runner, that's the
# short-lived credentials OIDC hands out for that specific run, so
# nothing sensitive ever ends up in this file or in git.
provider "aws" {
  region = var.aws_region
}