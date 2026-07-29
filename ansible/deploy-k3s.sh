#!/usr/bin/env bash
# Grabs the server's IP straight from Terraform's own output and uses
# it everywhere it's needed - the Ansible inventory, the TLS cert, and
# the kubeconfig - so nothing ever has to be hand-edited when the
# infrastructure changes.
set -euo pipefail

SERVER_IP=$(terraform -chdir=../terraform output -raw server_public_ip)
echo "Using server IP: $SERVER_IP"

ansible-playbook -i "${SERVER_IP}," install-k3s.yml \
  --extra-vars "ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-pipeline-key tls_san=${SERVER_IP}"

echo "Fetching kubeconfig..."
ssh -i ~/.ssh/devops-pipeline-key -o StrictHostKeyChecking=accept-new \
  ubuntu@"$SERVER_IP" "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/devops-pipeline-config
sed -i "s/127.0.0.1/${SERVER_IP}/" ~/.kube/devops-pipeline-config

echo "Done. Run this to use kubectl/helm against this cluster:"
echo "  export KUBECONFIG=~/.kube/devops-pipeline-config"