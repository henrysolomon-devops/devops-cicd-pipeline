#!/usr/bin/env bash
# Grabs the server's IP from SSM Parameter Store instead of Terraform's
# own output - since v9 moved off Terraform entirely, there's no local
# state file to read from anymore. infra.yml writes this parameter
# right after compute-stack.yaml finishes deploying, so by the time this
# script runs, the value is always current. Everything downstream (the
# Ansible inventory, the TLS cert, the kubeconfig) uses it exactly the
# same way it always has.
set -euo pipefail

AWS_REGION="us-east-1"

SERVER_IP=$(aws ssm get-parameter \
  --name "/devops-pipeline/server-public-ip" \
  --region "$AWS_REGION" \
  --query "Parameter.Value" \
  --output text)
echo "Using server IP: $SERVER_IP"

ansible-playbook -i "${SERVER_IP}," install-k3s.yml \
  --extra-vars "ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-pipeline-key tls_san=${SERVER_IP}"

echo "Fetching kubeconfig..."
mkdir -p ~/.kube
ssh -i ~/.ssh/devops-pipeline-key -o StrictHostKeyChecking=accept-new \
  ubuntu@"$SERVER_IP" "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/devops-pipeline-config
sed -i "s/127.0.0.1/${SERVER_IP}/" ~/.kube/devops-pipeline-config

echo "Done. Run this to use kubectl/helm against this cluster:"
echo "  export KUBECONFIG=~/.kube/devops-pipeline-config"

# Added in v9. The ALB is the actual front door now, so it's worth
# surfacing its address here too, right alongside the kubeconfig
# instructions - this is also written to SSM by infra.yml, the same way
# the server's own IP is above.
ALB_DNS=$(aws ssm get-parameter \
  --name "/devops-pipeline/alb-dns-name" \
  --region "$AWS_REGION" \
  --query "Parameter.Value" \
  --output text)
echo ""
echo "App is reachable through the ALB at:"
echo "  http://${ALB_DNS}/dev"
echo "  http://${ALB_DNS}/staging"
echo "  http://${ALB_DNS}/production"
