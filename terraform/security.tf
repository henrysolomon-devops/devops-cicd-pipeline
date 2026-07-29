# Firewall rules for the server. AWS blocks everything by default, so
# every port we actually need has to be opened explicitly here.
resource "aws_security_group" "server" {
  name        = "devops-pipeline-sg"
  description = "Allows SSH, k3s API, and app traffic for the devops pipeline server"
  vpc_id      = aws_vpc.main.id

  # SSH access for me and for Ansible. Locked to my own IP, no reason
  # to leave port 22 open to the entire internet.
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # k3s exposes the Kubernetes API on this port. Needed so kubectl and
  # helm on my local machine can reach the cluster once it's running.
  ingress {
    description = "k3s API server from my IP"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # Flask app port. Left open to everyone so I can check it from a
  # browser without extra hassle - this is a throwaway learning box,
  # not a real production server.
  ingress {
    description = "Flask app"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No outbound restrictions - the server needs to reach the internet
  # to install packages and pull the k3s installer script.
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