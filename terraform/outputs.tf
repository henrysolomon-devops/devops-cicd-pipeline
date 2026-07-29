# Now pointing at the Elastic IP instead of the instance's own public IP,
# since that's the address that actually stays put across rebuilds.
output "server_public_ip" {
  description = "Static public IP address of the EC2 instance (Elastic IP)"
  value       = aws_eip.server.public_ip
}