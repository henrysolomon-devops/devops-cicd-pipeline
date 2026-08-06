#!/usr/bin/env bash
# Same pattern as deploy-k3s.sh - grabs the Jenkins server's IP straight
# from Terraform's output, so nothing here ever has to be hand-edited
# when the infrastructure changes.
set -euo pipefail

JENKINS_SERVER_IP=$(terraform -chdir=../terraform output -raw jenkins_server_public_ip)
APP_SERVER_PRIVATE_IP=$(terraform -chdir=../terraform output -raw app_server_private_ip)
echo "Using Jenkins server IP: $JENKINS_SERVER_IP"

# The kubeconfig deploy-k3s.sh already fetched points at the app
# server's PUBLIC IP, since that's the only address a GitHub Actions
# runner (outside the VPC) can reach. Jenkins lives inside the same VPC
# though, so it should talk to the app server over the private network
# instead - that's both more correct and what actually makes the
# standing security group rule (source: jenkins_server's own security
# group) match, since public-IP traffic routes out through the
# internet gateway and no longer looks like it's coming from inside
# the VPC. This builds a private-IP copy of the kubeconfig just for
# what gets copied onto the Jenkins server below.
sed -E "s#(https://)[0-9.]+(:6443)#\1${APP_SERVER_PRIVATE_IP}\2#" \
  "$HOME/.kube/devops-pipeline-config" > "$HOME/.kube/devops-pipeline-config-internal"

ansible-playbook -i "${JENKINS_SERVER_IP}," install-jenkins.yml \
  --extra-vars "ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-pipeline-key kubeconfig_src=$HOME/.kube/devops-pipeline-config-internal ghcr_pat=${GHCR_PAT}"

echo "Done. Jenkins should be reachable at:"
echo "  http://${JENKINS_SERVER_IP}:8080"
