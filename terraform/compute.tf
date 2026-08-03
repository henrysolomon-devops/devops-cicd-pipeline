# Importing the public key I generated locally instead of letting AWS
# create a new key pair. This way the private key never has to touch
# AWS at all - only the public half gets uploaded. Both servers below
# share this same key pair, since they're both mine to SSH into.
resource "aws_key_pair" "devops_pipeline" {
  key_name   = "devops-pipeline-key"
  public_key = file(var.public_key_path)
}

# Always grab the latest official Ubuntu 24.04 image instead of
# hardcoding an AMI ID, since AMI IDs go stale and vary by region.
# Both instances below are built from this same AMI.
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

# The main application server: runs k3s and the dev/staging/production
# namespaces. Renamed from the generic "server" to "app_server" in v7,
# now that a second, differently-purposed server exists alongside it.
# Bumped from t3.micro to t3.small to t3.medium over v5-v6, since a
# full Kubernetes control plane (plus ArgoCD's own components) needs
# more headroom than the smaller sizes offer.
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_server.id]
  key_name               = aws_key_pair.devops_pipeline.key_name

  tags = {
    Name = "devops-pipeline-app-server"
  }
}

# A static public IP that stays locked to the app server no matter what
# happens underneath it - resize, stop/start, anything. Without this,
# every change to the server hands us a brand new IP and we'd have to
# go chase it down across Ansible, the TLS cert, and the kubeconfig
# every single time.
resource "aws_eip" "app_server" {
  instance = aws_instance.app_server.id
  domain   = "vpc"

  tags = {
    Name = "devops-pipeline-app-server-eip"
  }
}

# New in v7: a small, separate instance that only runs Jenkins. Kept
# deliberately lightweight - it's not running Kubernetes or anything
# else, just building images and driving the pipeline, so t3.micro is
# plenty. Living in its own instance (rather than alongside k3s on
# app_server) keeps the two concerns cleanly separated, the same way
# CI servers and the clusters they deploy to are usually split apart
# in real infrastructure.
resource "aws_instance" "jenkins_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jenkins_server.id]
  key_name               = aws_key_pair.devops_pipeline.key_name

  tags = {
    Name = "devops-pipeline-jenkins-server"
  }
}

# Same reasoning as app_server's EIP above: a stable address so the
# Jenkins UI is always reachable at the same URL, and so nothing has
# to be re-pointed every time this instance gets rebuilt.
resource "aws_eip" "jenkins_server" {
  instance = aws_instance.jenkins_server.id
  domain   = "vpc"

  tags = {
    Name = "devops-pipeline-jenkins-server-eip"
  }
}

