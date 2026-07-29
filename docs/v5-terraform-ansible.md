# v5: Terraform (VPC + EC2) + Ansible (k3s install)

**Concept demonstrated:** Infrastructure as Code, Configuration Management

## Why Terraform and Ansible?

Through v4, everything ran on a local `kind` cluster on the same machine as the code — no cloud cost, but also not a real server. v5 moves the target onto an actual AWS EC2 instance for the first time, and this introduces two new concepts:

- **Terraform (Infrastructure as Code):** instead of clicking together a VPC and a server in the AWS console, the infrastructure is defined as code. `terraform plan` shows exactly what will be created, changed, or destroyed before anything happens, and `terraform destroy` tears it all down cleanly afterward, no manual cleanup, no leftover resources.
- **Ansible (Configuration Management):** Terraform only creates the server, it doesn't install anything on it. Ansible connects over SSH and installs software on an existing machine, in this case, k3s.

**Why k3s instead of a full Kubernetes install?** A full `kubeadm`-based cluster is designed to manage multiple nodes and carries more setup complexity than a single EC2 instance needs. k3s is a lightweight Kubernetes distribution built for exactly this case, a single server, real Kubernetes APIs, a much smaller footprint.

## What's included

- `terraform/` : a VPC, a public subnet, an Internet Gateway, a route table, a security group, an EC2 instance, and a static Elastic IP
- `ansible/install-k3s.yml` : installs k3s via its official install script and waits for the node to report `Ready`
- `ansible/deploy-k3s.sh` : reads the server's IP directly from Terraform's output and uses it for the Ansible connection, the k3s TLS certificate, and the kubeconfig, so nothing has to be hand-edited when the infrastructure changes
- `helm/devops-pipeline/values-ec2.yaml` : a Helm values override used to manually verify the chart on this cluster (see Testing below)

## One-time setup: AWS credentials

Terraform needs AWS credentials before it can create anything. This only needs to be done once per machine:

```bash
# Install the AWS CLI
curl "https://awscliv2.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

In the AWS Console, create a dedicated IAM user (not the root account) scoped to EC2 permissions only:

1. **IAM → Users → Create user**, e.g. `terraform-devops-pipeline`
2. Attach the `AmazonEC2FullAccess` policy
3. **Security credentials → Create access key** (choose "Command Line Interface")

Then configure the CLI with that key:

```bash
aws configure
# AWS Access Key ID:     <from the IAM user>
# AWS Secret Access Key: <from the IAM user>
# Default region name:   us-east-1
# Default output format: json
```

Verify it worked:

```bash
aws sts get-caller-identity
```

Using a scoped IAM user instead of root credentials means that even if these credentials were ever exposed, the damage would be limited to EC2 resources, not full account access.

## One-time setup: SSH key pair

```bash
ssh-keygen -t ed25519 -f ~/.ssh/devops-pipeline-key -C "devops-pipeline"
```

Terraform imports the public half of this key into AWS; the private half never leaves the local machine.

## Building the infrastructure

```bash
cd terraform
terraform init
terraform plan -var="my_ip=$(curl -s ifconfig.me)"
terraform apply -var="my_ip=$(curl -s ifconfig.me)"
```

`my_ip` restricts SSH and the k3s API port to the operator's own IP address; the app port (5000) is left open to any source for easy browser testing.

## Installing k3s

```bash
cd ../ansible
./deploy-k3s.sh
```

This single script installs k3s, configures its TLS certificate for the server's public IP, and fetches a working kubeconfig to the local machine. To use it:

```bash
export KUBECONFIG=~/.kube/devops-pipeline-config
kubectl get nodes
```

## Testing

**Infrastructure:**

```bash
terraform plan -var="my_ip=$(curl -s ifconfig.me)"
# Plan: 8 to add, 0 to change, 0 to destroy.

terraform apply -var="my_ip=$(curl -s ifconfig.me)"
# Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

**k3s:**

```bash
kubectl get nodes
# NAME            STATUS   ROLES           AGE   VERSION
# ip-10-0-1-xxx   Ready    control-plane   ...   v1.36.2+k3s1
```

**The app, deployed manually to confirm the infrastructure is genuinely usable (not automated yet, see "What's next" below):**

```bash
helm install devops-pipeline helm/devops-pipeline \
  -f helm/devops-pipeline/values-ec2.yaml \
  --set service.type=LoadBalancer \
  --set service.port=5000

kubectl get pods
```

Visited `http://<server-ip>:5000/`, `/api/status`, and `/health` directly, no `kubectl port-forward` needed, since switching the Service to `LoadBalancer` lets k3s's built-in Klipper load balancer expose the app on the node's public IP directly. Confirmed the app responded with the correct version, environment (`ec2-test`), and hostname, matching the same behavior verified in v1 through v4.

**Cleanup, per the project's cost and safety rules:**

```bash
terraform destroy -var="my_ip=$(curl -s ifconfig.me)"
# Destroy complete! Resources: 9 destroyed.
```

## What's next

v5.1 will extend the existing v4 GitHub Actions pipeline to deploy onto this EC2/k3s server automatically, replacing the manual `helm install` step used here.