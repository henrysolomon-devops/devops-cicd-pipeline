#!/usr/bin/env bash
# Same pattern as deploy-k3s.sh - grabs the Jenkins server's IP straight
# from Terraform's output, so nothing here ever has to be hand-edited
# when the infrastructure changes. Two extra pieces of input this one
# needs that deploy-k3s.sh didn't: the app server's kubeconfig (already
# sitting at ~/.kube/devops-pipeline-config after deploy-k3s.sh ran)
# and the GHCR push token, both passed straight through to Ansible.
set -euo pipefail

JENKINS_SERVER_IP=$(terraform -chdir=../terraform output -raw jenkins_server_public_ip)
echo "Using Jenkins server IP: $JENKINS_SERVER_IP"

ansible-playbook -i "${JENKINS_SERVER_IP}," install-jenkins.yml \
  --extra-vars "ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-pipeline-key kubeconfig_src=$HOME/.kube/devops-pipeline-config ghcr_pat=${GHCR_PAT}"

echo "Done. Jenkins should be reachable at:"
echo "  http://${JENKINS_SERVER_IP}:8080"
