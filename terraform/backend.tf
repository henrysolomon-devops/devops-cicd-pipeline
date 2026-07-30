# This block tells Terraform where to store its state file.
# Instead of keeping it on the local disk (which doesn't exist once
# this runs on a temporary GitHub-hosted runner), the state is stored
# remotely in an S3 bucket, so every run - whether triggered today or
# next month, from this machine or a fresh GitHub runner - reads and
# writes the same shared source of truth.
terraform {
  backend "s3" {
    bucket = "devops-cicd-pipeline-tfstate-henrysolomon"
    key    = "devops-cicd-pipeline/terraform.tfstate"
    region = "us-east-1"

    # Terraform 1.10+ can handle state locking natively through S3's
    # conditional writes, so a separate DynamoDB table just for
    # locking is no longer necessary.
    use_lockfile = true
  }
}