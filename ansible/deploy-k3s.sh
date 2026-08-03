#!/usr/bin/env bash
# Grabs the app server's IP straight from Terraform's own output and
# uses it everywhere it's needed - the Ansible inventory, the TLS cert,
# and the kubeconfig - so nothing ever has to be hand-edited when the
# infrastructure changes. Renamed the variable to APP_SERVER_IP in v7,
# now that a second server (Jenkins) exists alongside this one.
set -euo pipefail

APP_SERVER_IP=$(terraform -chdir=../terraform output -raw app_server_public_ip)
echo "Using app server IP: $APP_SERVER_IP"

ansible-playbook -i "${APP_SERVER_IP}," install-k3s.yml \
  --extra-vars "ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-pipeline-key tls_san=${APP_SERVER_IP}"

echo "Fetching kubeconfig..."
mkdir -p ~/.kube
ssh -i ~/.ssh/devops-pipeline-key -o StrictHostKeyChecking=accept-new \
  ubuntu@"$APP_SERVER_IP" "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/devops-pipeline-config
sed -i "s/127.0.0.1/${APP_SERVER_IP}/" ~/.kube/devops-pipeline-config

echo "Done. Run this to use kubectl/helm against this cluster:"
echo "  export KUBECONFIG=~/.kube/devops-pipeline-config"