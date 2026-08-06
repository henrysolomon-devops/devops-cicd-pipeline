# Now pointing at the Elastic IP instead of the instance's own public IP,
# since that's the address that actually stays put across rebuilds.
output "app_server_public_ip" {
  description = "Static public IP address of the app/k3s server (Elastic IP)"
  value       = aws_eip.app_server.public_ip
}

# New in v7 - used to build a kubeconfig for the Jenkins server that
# talks to the k3s API over the internal VPC network, rather than
# round-tripping out through the internet gateway and back in via the
# public IP (which also breaks the security-group-based access rule,
# since that traffic no longer looks like it's coming from inside the
# VPC once it's gone out through the gateway).
output "app_server_private_ip" {
  description = "Private IP address of the app/k3s server, for in-VPC access from the Jenkins server"
  value       = aws_instance.app_server.private_ip
}

# New in v7 - the Jenkins server's own stable address. Used to reach
# the Jenkins UI at http://<this-ip>:8080, and by infra.yml/Ansible to
# know where to install and configure Jenkins.
output "jenkins_server_public_ip" {
  description = "Static public IP address of the Jenkins server (Elastic IP)"
  value       = aws_eip.jenkins_server.public_ip
}