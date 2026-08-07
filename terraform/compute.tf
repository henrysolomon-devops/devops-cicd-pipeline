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
