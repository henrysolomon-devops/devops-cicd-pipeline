# v2: Kubernetes (kind) + dev/staging/production namespaces

**Concept demonstrated:** Orchestration, environment isolation

## Why Kubernetes?

Docker alone can run a single container, but it doesn't answer questions like: what happens if a container crashes? How do you run multiple copies for reliability? Kubernetes is the orchestration layer that handles this. You declare the desired state (for example "always keep 2 replicas running"), and Kubernetes continuously works to match reality to that state, restarting or recreating Pods automatically. This is usually called self-healing.

For local development, this project uses [`kind`](https://kind.sigs.k8s.io/) (Kubernetes IN Docker), which runs a real Kubernetes cluster using Docker containers as nodes. No cloud cost, same real Kubernetes commands. A real server-based cluster (`k3s` on an actual machine) comes later, in v5.

## Namespaces

Instead of three separate servers, this project uses three Kubernetes namespaces inside the same local cluster to isolate environments:

- `dev` : early testing
- `staging` : pre-release testing
- `production` : the stable, live version

## Setup (historical, superseded by Helm in v3)

> **Note:** the commands below show how v2 originally deployed the app, using raw `kubectl apply` on plain YAML manifests. Starting in v3, these manifests were rewritten as a Helm chart, and deployment now happens through `helm install`/`helm upgrade` instead. The `k8s/` folder shown here no longer exists in the repo; it's kept in this doc purely as a historical record of how the project got here. See [`docs/v3-helm.md`](./v3-helm.md) for the current deployment method.

```bash
# Install kubectl (the CLI used to talk to any Kubernetes cluster)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install kind (runs a local Kubernetes cluster using Docker)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create the local cluster
kind create cluster --name devops-pipeline

# Create the three environment namespaces
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace production

# Load the v1 Docker image directly into the kind cluster
# (no registry needed for local development)
kind load docker-image devops-cicd-pipeline:v1.0.0 --name devops-pipeline

# Deploy to each namespace
kubectl apply -f k8s/deployment.yaml -n dev
kubectl apply -f k8s/service.yaml -n dev
kubectl apply -f k8s/deployment.yaml -n staging
kubectl apply -f k8s/service.yaml -n staging
kubectl apply -f k8s/deployment.yaml -n production
kubectl apply -f k8s/service.yaml -n production
```

## Testing

```bash
kubectl get pods -n dev
kubectl port-forward -n dev service/flask-app-service 8080:80
```

Visit `http://localhost:8080`.

## Self-healing demo

```bash
kubectl get pods -n dev
kubectl delete pod <pod-name> -n dev
kubectl get pods -n dev
```

A new Pod gets created automatically to replace the deleted one, keeping the replica count at the declared value. No manual intervention needed.
