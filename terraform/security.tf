resource "aws_security_group" "server" {
  name        = "devops-pipeline-sg"
  description = "Security group for the EC2/k3s server - SSH is locked to me, everything else starts closed and opens only for the length of a workflow run"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH, only from my own machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # No ingress rules here for the k3s API (6443) or the app ports
  # (5000/5001/5002) on purpose - those get added and removed
  # dynamically by the workflows that actually need them, see
  # infra.yml and deploy.yml.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-pipeline-sg"
  }
}

output "security_group_id" {
  value = aws_security_group.server.id
}