# The AWS region where everything gets created. Kept as a variable
# instead of hardcoded in provider.tf so I can override it later without
# touching the provider config itself.
variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

# My own public IP, so SSH and the k3s API are only reachable from me,
# not the whole internet. No default on purpose - this depends on
# whoever's running the code, so it has to be passed in each time.
variable "my_ip" {
  description = "Your public IP address, for restricting SSH and k3s API access"
  type        = string
}

# Path to the public key I generated with ssh-keygen. The matching
# private key is what I'll actually use to SSH in and what Ansible
# will use to connect and run the playbook.
variable "public_key_path" {
  description = "Path to the local SSH public key file"
  type        = string
  default     = "~/.ssh/devops-pipeline-key.pub"
}