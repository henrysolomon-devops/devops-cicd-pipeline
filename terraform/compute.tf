# Importing the public key I generated locally instead of letting AWS
# create a new key pair. This way the private key never has to touch
# AWS at all - only the public half gets uploaded.
resource "aws_key_pair" "devops_pipeline" {
  key_name   = "devops-pipeline-key"
  public_key = file(var.public_key_path)
}

# Always grab the latest official Ubuntu 24.04 image instead of
# hardcoding an AMI ID, since AMI IDs go stale and vary by region.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Bumped again in v8, from t3.medium to t3.large. t3.medium was already
# a stretch once ArgoCD's own components were added in v6, and v8 adds
# a full kube-prometheus-stack (Prometheus, Grafana, node-exporter,
# kube-state-metrics) on top of everything already running - k3s,
# ArgoCD, the app, and now a small Redis per namespace. Since the server
# is only ever up while actively testing, not 24/7, the extra cost of
# t3.large over t3.medium is negligible in practice.
resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.server.id]
  key_name               = aws_key_pair.devops_pipeline.key_name

  # Added in v8.1. This is what actually lets Loki, running inside k3s on this
  # instance, reach the manually-created S3 bucket for log storage - the role
  # and its scoped policy are defined in iam.tf, this line is just what attaches
  # the resulting Instance Profile to the server itself. Changing this value
  # doesn't force AWS to replace the instance; it's applied as an in-place
  # association, the same way you could swap it from the AWS Console without
  # stopping the server.
  iam_instance_profile = aws_iam_instance_profile.loki_s3_access.name

  # Added in v8.1. AWS defaults the IMDS hop limit to 1, which is enough for a
  # process running directly on the host, but Loki runs one network layer
  # deeper - inside a container, inside k3s, on this same instance. That extra
  # hop means the default limit silently blocks Loki from ever reaching the
  # metadata service, so it would never actually get real AWS credentials
  # despite the IAM Instance Profile above being attached correctly. Raising
  # this to 2 is the standard fix for any containerized workload that needs
  # instance-role credentials without IRSA.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Added in v8. The AMI's default root volume (under 8GB) was never a
  # problem before, but pulling every image for k3s, ArgoCD, and the
  # full kube-prometheus-stack (Prometheus, Grafana, node-exporter,
  # kube-state-metrics, plus the operator itself) at the same time fills
  # it completely - confirmed directly on the server: kubectl reported
  # DiskPressure and started evicting Pods, not a memory problem. 30GB
  # leaves comfortable headroom without being wasteful for a box that's
  # only ever up while actively testing.
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "devops-pipeline-server"
  }
}

# A static public IP that stays locked to the instance no matter what
# happens underneath it - resize, stop/start, anything. Without this,
# every change to the server hands us a brand new IP and we'd have to
# go chase it down across Ansible, the TLS cert, and the kubeconfig
# every single time.
resource "aws_eip" "server" {
  instance = aws_instance.server.id
  domain   = "vpc"

  tags = {
    Name = "devops-pipeline-eip"
  }
}
