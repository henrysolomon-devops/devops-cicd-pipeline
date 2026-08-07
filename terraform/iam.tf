# k3s here doesn't have IRSA (that's an EKS-specific feature for giving individual
# Pods their own AWS identity), so there's no clean way to hand Loki's Pod its own
# scoped credential the way a real EKS cluster could. The next best option, and the
# one used here, is an IAM Instance Profile attached to the EC2 instance itself -
# every process on that instance, including Loki running inside k3s, can reach S3
# through the instance's own temporary credentials, with no access key stored
# anywhere in Git, Ansible, or a Kubernetes Secret.

# This bucket is created once, by hand, outside of Terraform entirely - the same
# pattern already used for the Terraform state bucket back in v5.1. It has to live
# outside the regular destroy/apply cycle, or every `terraform destroy` would wipe
# out the log history that's the whole point of storing it in S3 in the first place.
# Since Terraform doesn't manage the bucket itself, only its name is referenced here.
variable "loki_logs_bucket_name" {
  description = "Name of the manually-created S3 bucket Loki uses for log chunk storage"
  type        = string
  default     = "devops-cicd-pipeline-loki-logs"
}

# The trust policy below is what allows EC2 (and only EC2) to assume this role.
data "aws_iam_policy_document" "loki_ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "loki_s3_access" {
  name               = "devops-cicd-pipeline-loki-s3-access"
  assume_role_policy = data.aws_iam_policy_document.loki_ec2_trust.json
}

# Scoped to exactly the one bucket Loki needs, nothing else in the account - the
# same "least privilege" principle already used for the Terraform state bucket
# policy back in v5.1.
data "aws_iam_policy_document" "loki_s3_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.loki_logs_bucket_name}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.loki_logs_bucket_name}"]
  }
}

resource "aws_iam_role_policy" "loki_s3_access" {
  name   = "loki-s3-bucket-access"
  role   = aws_iam_role.loki_s3_access.id
  policy = data.aws_iam_policy_document.loki_s3_permissions.json
}

# EC2 doesn't accept an IAM role directly - it has to be wrapped in an Instance
# Profile first, which is the resource actually attached to the instance in
# compute.tf.
resource "aws_iam_instance_profile" "loki_s3_access" {
  name = "devops-cicd-pipeline-loki-s3-access"
  role = aws_iam_role.loki_s3_access.name
}
