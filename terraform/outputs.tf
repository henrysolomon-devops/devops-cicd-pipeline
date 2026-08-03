# Now pointing at the Elastic IP instead of the instance's own public IP,
# since that's the address that actually stays put across rebuilds.
output "app_server_public_ip" {
  description = "Static public IP address of the app/k3s server (Elastic IP)"
  value       = aws_eip.app_server.public_ip
}

# New in v7 - the Jenkins server's own stable address. Used to reach
# the Jenkins UI at http://<this-ip>:8080, and by infra.yml/Ansible to
# know where to install and configure Jenkins.
output "jenkins_server_public_ip" {
  description = "Static public IP address of the Jenkins server (Elastic IP)"
  value       = aws_eip.jenkins_server.public_ip
}