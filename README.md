# DevOps CI/CD Pipeline

A complete, end-to-end DevOps CI/CD pipeline built incrementally, one tool
at a time. Each version below adds exactly one new concept to an
already-working system, from containerizing a simple app all the way to
Kubernetes, Infrastructure as Code, GitOps, CI/CD, and observability.

The goal isn't just to run the commands, but to understand *why* each tool
is used. See [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) for the full roadmap,
conventions, and reasoning behind every decision.

## Roadmap

| Version | What's added                                              | Concept demonstrated                            | Status |
|---------|------------------------------------------------------------|--------------------------------------------------|--------|
| v1.0    | Flask app + Docker + HTML dashboard                        | Containerization                                  | ✅ Done |
| v2.0    | Kubernetes (`kind`) + dev/staging/production namespaces     | Orchestration, environment isolation              | ✅ Done |
| v3.0    | Helm chart                                                  | Package management for Kubernetes                | 🔜 Next |
| v4.0    | GitHub Actions (branch-based deploy)                        | CI/CD pipeline                                    | ⏳ Planned |
| v5.0    | Terraform (EC2 + VPC) + Ansible (k3s install)               | Infrastructure as Code, Configuration Management  | ⏳ Planned |
| v6.0    | ArgoCD                                                      | GitOps-based Continuous Deployment                | ⏳ Planned |
| v7.0    | Jenkins pipeline (alternative to Actions)                   | Alternative CI tooling                            | ⏳ Planned |
| v8.0    | Prometheus + Grafana                                        | Observability & monitoring                        | ⏳ Planned |
| v9.0    | Load Balancer + AWS CloudFormation                          | Networking, alternative IaC                       | ⏳ Planned |

## Project structure

```
devops-cicd-pipeline/
├── app/         # Application source code (v1)
├── docker/      # Dockerfile + .dockerignore (v1)
├── k8s/         # Kubernetes manifests (v2)
├── helm/        # Helm chart (v3)
├── .github/     # GitHub Actions workflows (v4)
├── terraform/   # Infrastructure as Code (v5)
├── ansible/     # Configuration management (v5)
├── argocd/      # GitOps application definitions (v6)
├── jenkins/     # Jenkins pipeline (v7)
├── monitoring/  # Prometheus + Grafana configs (v8)
└── docs/        # Diagrams and demos (v9+)
```

Each tool gets its own folder at the repo root, added as the version that
introduces it is built, nothing is duplicated per version.


## v1: Flask app + Docker + HTML dashboard

A small Flask application with three routes:

- `/` — an HTML dashboard showing the app version, hostname, server time,
  and a live health status
- `/api/status` — the same information as JSON
- `/health` — a minimal health check endpoint, used later by Kubernetes
  liveness/readiness probes (v2 onward)

### Running locally (without Docker)

```bash
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 app.py
```

Visit `http://localhost:5000`.

### Running with Docker

```bash
docker build -f docker/Dockerfile -t devops-cicd-pipeline:v1.0.0 .
docker run -d -p 5000:5000 --name devops-app devops-cicd-pipeline:v1.0.0
```

Visit `http://localhost:5000`

Stop and remove the container when done:

```bash
docker stop devops-app
docker rm devops-app
```


## v2: Kubernetes (kind) + dev/staging/production namespaces

Docker alone can run a single container, but it can't answer questions
like: what happens if a container crashes? How do we run multiple
copies for reliability? Kubernetes is the orchestration layer that
answers these questions — you declare the desired state (e.g. "always
keep 2 replicas running"), and Kubernetes continuously works to match
reality to that state, restarting or recreating Pods automatically
(self-healing).

For local development, this project uses [`kind`](https://kind.sigs.k8s.io/)
(Kubernetes IN Docker), which runs a real Kubernetes cluster using Docker
containers as nodes — no cloud cost, same real Kubernetes commands. A real
server-based cluster (`k3s` on an actual machine) comes later, in v5.

### Namespaces

Instead of three separate servers, this project uses three Kubernetes
namespaces inside the same local cluster to isolate environments:

- `dev` — early testing
- `staging` — pre-release testing
- `production` — the stable, live version

### Setup

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

### Testing

```bash
kubectl get pods -n dev
kubectl port-forward -n dev service/flask-app-service 8080:80
```

Visit `http://localhost:8080`.

### Self-healing demo

```bash
kubectl get pods -n dev
kubectl delete pod <pod-name> -n dev
kubectl get pods -n dev
```

A new Pod is created automatically to replace the deleted one, keeping
the replica count at the declared value — no manual intervention needed.


## License

MIT - see [`LICENSE`](./LICENSE).
