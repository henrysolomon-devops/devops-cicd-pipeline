resource "aws_security_group" "server" {
  name        = "devops-pipeline-sg"
  description = "Security group for the EC2/k3s server - SSH and app ports are always open for me, GitHub runners get temporary access per workflow run"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH, only from my own machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Always open for me so I can check the app in a browser or run
  # kubectl manually anytime, without waiting for a workflow run to
  # temporarily open a port first. This survives every destroy/apply
  # cycle, unlike the manual console rule I kept losing.
  ingress {
    description = "App ports (dev/staging/production), always reachable from my own machine"
    from_port   = 5000
    to_port     = 5002
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "k3s API, always reachable from my own machine"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Added in v8, same reasoning as the app ports above: Grafana runs
  # with no login (see monitoring/values.yaml), so this permanent,
  # IP-scoped rule is the only thing actually protecting it - there's
  # no auth layer behind it to fall back on.
  ingress {
    description = "Grafana UI, always reachable from my own machine"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # No permanent ingress rules here for GitHub's runners - those open
  # and close dynamically per workflow run via the AWS CLI, see
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
