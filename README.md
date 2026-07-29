# DevOps CI/CD Pipeline

A complete, end-to-end DevOps CI/CD pipeline built incrementally, one tool at a time. Each version adds exactly one new concept to an already-working system, starting from containerizing a simple app and working up to Kubernetes, Infrastructure as Code, GitOps, CI/CD, and observability.

The goal isn't just to run the commands, but to understand why each tool is used. See [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) for the full roadmap, conventions, and reasoning behind every decision. Each version below also has its own detailed guide under [`docs/`](./docs), covering setup, testing, and the reasoning behind that version specifically.

## Roadmap

| Version | What's added | Concept demonstrated | Status |
|---------|---------------|------------------------|--------|
| v1.0 | Flask app + Docker + HTML dashboard | Containerization | ✅ Done |
| v2.0 | Kubernetes (`kind`) + dev/staging/production namespaces | Orchestration, environment isolation | ✅ Done |
| v3.0 | Helm chart | Package management for Kubernetes | ✅ Done |
| v4.0 | GitHub Actions (branch-based deploy) | CI/CD pipeline | ✅ Done |
| v5.0 | Terraform (EC2 + VPC) + Ansible (k3s install) | Infrastructure as Code, Configuration Management | ✅ Done |
| v5.1 | GitHub Actions deploy to the v5 EC2/k3s server | Extending existing CI/CD to a real cloud target | 🔜 Next |
| v6.0 | ArgoCD | GitOps-based Continuous Deployment | ⏳ Planned |
| v7.0 | Jenkins pipeline (alternative to Actions) | Alternative CI tooling | ⏳ Planned |
| v8.0 | Prometheus + Grafana | Observability & monitoring | ⏳ Planned |
| v9.0 | Load Balancer + AWS CloudFormation | Networking, alternative IaC | ⏳ Planned |

## Project structure

Each tool gets its own folder at the repo root, added as the version that introduces it gets built. The layout below shows the full planned structure; folders marked with a later version number don't exist yet.

    devops-cicd-pipeline/
    ├── app/         # Application source code (v1)
    ├── docker/      # Dockerfile + .dockerignore (v1)
    ├── helm/        # Helm chart (v3, replaces the old k8s/ manifests from v2)
    ├── .github/     # GitHub Actions workflows (v4)
    ├── terraform/   # Infrastructure as Code (v5)
    ├── ansible/     # Configuration management (v5)
    ├── argocd/      # GitOps application definitions (v6, not yet added)
    ├── jenkins/     # Jenkins pipeline (v7, not yet added)
    ├── monitoring/  # Prometheus + Grafana configs (v8, not yet added)
    └── docs/        # Detailed per-version guides (setup, testing, reasoning)

## v1: Flask app + Docker + HTML dashboard

A small Flask application containerized with Docker. It exposes an HTML dashboard, a JSON status endpoint, and a health check endpoint used later by Kubernetes probes.

📄 [Full guide: setup, testing, and reasoning](./docs/v1-flask-docker.md)

## v2: Kubernetes (kind) + dev/staging/production namespaces

The app deployed onto a local Kubernetes cluster (`kind`), split across three namespaces (`dev`, `staging`, `production`) to isolate environments without needing separate servers. Demonstrates self-healing when a Pod is deleted.

📄 [Full guide: setup, testing, and reasoning](./docs/v2-kubernetes.md)

## v3: Helm chart

The raw Kubernetes manifests from v2 were rewritten as a Helm chart, with per-environment values files replacing hand-edited YAML. Also demonstrates `helm upgrade` and `helm rollback` in practice.

📄 [Full guide: setup, testing, and reasoning](./docs/v3-helm.md)

## v4: GitHub Actions

A self-hosted GitHub Actions runner, installed directly on the same Linux machine that runs the kind cluster, so workflows can reach it the same way `kubectl` and `helm` already do locally. Every push to `main` builds a fresh image, pushes it to GitHub Container Registry (ghcr.io - our first use of it, since kind no longer needs it), and rolls it out to dev, staging, and production in that order. Staging and production each require a manual approval, using GitHub Environments, before the rollout proceeds - so nothing reaches production without a human actually checking it first. Also adds an `APP_ENV` variable to the app itself, so the dashboard shows which environment actually answered the request.

📄 [Full guide: setup, testing, and reasoning](./docs/v4-github-actions.md)

## v5: Terraform (VPC + EC2) + Ansible (k3s install)

Infrastructure moves off the local machine for the first time: Terraform provisions a VPC, subnet, and EC2 instance on AWS with a static Elastic IP, and Ansible installs k3s — a lightweight Kubernetes distribution well-suited to a single server — on top of it. A helper script (`ansible/deploy-k3s.sh`) reads the server's IP straight from Terraform's output and handles the k3s install, TLS configuration, and kubeconfig retrieval in one step. The existing v3 Helm chart deploys cleanly onto this cluster, pulling the image already published to GitHub Container Registry by the v4 pipeline — confirming the infrastructure is genuinely usable, not just reachable. Following the project's cost and safety rules, the server only runs for testing and is torn down afterward with `terraform destroy`.

📄 [Full guide: setup, testing, and reasoning](./docs/v5-terraform-ansible.md)

## License

MIT, see [`LICENSE`](./LICENSE).