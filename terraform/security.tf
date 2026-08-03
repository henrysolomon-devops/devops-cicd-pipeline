resource "aws_security_group" "app_server" {
  name        = "devops-pipeline-app-server-sg"
  description = "Security group for the app/k3s server - SSH, app ports, and the k3s API are always open for me; the Jenkins server also has standing access to the k3s API"
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

  # New in v7: the Jenkins server runs the pipeline's deploy stages
  # directly, using a kubeconfig that points at this cluster's API, so
  # it needs standing access here too, not just a temporary hole opened
  # during infra setup like GitHub's runners get. This rule is scoped
  # to the Jenkins server's own security group rather than an IP or
  # CIDR, so access follows the instance itself even if its address
  # ever changed.
  ingress {
    description     = "k3s API, standing access for the Jenkins server"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_server.id]
  }

  # No permanent ingress rule here for GitHub's runners - that access
  # opens and closes dynamically per workflow run via the AWS CLI, see
  # infra.yml. deploy.yml doesn't touch this security group at all
  # since v6 - ArgoCD reads from Git on its own, so nothing outside
  # the cluster needs to reach in for a regular app deploy.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-pipeline-app-server-sg"
  }
}

# New in v7: a separate security group for the Jenkins server. Kept
# apart from the app server's group on purpose, so Jenkins doesn't end
# up with the app ports open, and the app server doesn't end up with
# the Jenkins UI port open - each security group only exposes exactly
# what its own instance actually needs.
resource "aws_security_group" "jenkins_server" {
  name        = "devops-pipeline-jenkins-server-sg"
  description = "Security group for the Jenkins server - SSH and the Jenkins UI are always open for me; GitHub runners get temporary SSH access per workflow run to install Jenkins via Ansible"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH, only from my own machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Jenkins UI, only from my own machine"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # No permanent ingress rule here for GitHub's runners either - same
  # pattern as app_server above, opened dynamically in infra.yml just
  # long enough for Ansible to install and configure Jenkins.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-pipeline-jenkins-server-sg"
  }
}

output "app_server_security_group_id" {
  value = aws_security_group.app_server.id
}

output "jenkins_server_security_group_id" {
  value = aws_security_group.jenkins_server.id
}