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
| v5.1 | GitHub Actions deploy to the v5 EC2/k3s server | Extending existing CI/CD to a real cloud target | ✅ Done |
| v6.0 | ArgoCD | GitOps-based Continuous Deployment | ✅ Done |
| v7.0 | Jenkins pipeline (alternative to Actions) | Alternative CI tooling | ✅ Done |
| v8.0 | Prometheus + Grafana | Observability & monitoring | 🔜 Next |
| v9.0 | Load Balancer + AWS CloudFormation | Networking, alternative IaC | ⏳ Planned |

## Project structure

Each tool gets its own folder at the repo root, added as the version that introduces it gets built. The layout below shows the full planned structure; folders marked with a later version number don't exist yet.

    devops-cicd-pipeline/
    ├── app/         # Application source code (v1)
    ├── docker/      # Dockerfile + .dockerignore (v1)
    ├── helm/        # Helm chart (v3, replaces the old k8s/ manifests from v2)
    ├── .github/     # GitHub Actions workflows (v4, extended in v5.1)
    ├── terraform/   # Infrastructure as Code (v5, remote state added in v5.1)
    ├── ansible/     # Configuration management (v5)
    ├── argocd/      # GitOps application definitions (v6)
    ├── jenkins/     # Jenkins pipeline (v7)
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

A self-hosted GitHub Actions runner, installed directly on the same Linux machine that runs the kind cluster, so workflows can reach it the same way `kubectl` and `helm` already do locally. Every push to `main` builds a fresh image, pushes it to GitHub Container Registry (ghcr.io), and rolls it out to dev, staging, and production in that order, with manual approval gates on staging and production. Also adds an `APP_ENV` variable to the app itself, so the dashboard shows which environment actually answered the request.

📄 [Full guide: setup, testing, and reasoning](./docs/v4-github-actions.md)

## v5: Terraform (VPC + EC2) + Ansible (k3s install)

Infrastructure moves off the local machine for the first time: Terraform provisions a VPC, subnet, and EC2 instance on AWS with a static Elastic IP, and Ansible installs k3s on top of it. The existing Helm chart deploys cleanly onto this cluster, confirming the infrastructure is genuinely usable. At this stage the server was still built, tested, and torn down manually.

📄 [Full guide: setup, testing, and reasoning](./docs/v5-terraform-ansible.md)

## v5.1: Migrate all environments to AWS EC2/k3s

The local `kind` cluster and self-hosted runner are retired. All three environments (`dev`, `staging`, `production`) now live permanently on the v5 EC2/k3s server, each reachable on its own port. A new `infra.yml` workflow builds and tears down the server on demand, authenticating to AWS via OIDC instead of a stored access key. `deploy.yml` now runs entirely on GitHub-hosted runners and deploys directly onto this server, with a new approval gate confirming the server is up before anything tries to reach it.

📄 [Full guide: setup, testing, and reasoning](./docs/v5.1-aws-migration.md)

## v6: ArgoCD (GitOps-based Continuous Deployment)

Deployment moved from GitHub Actions pushing directly into the cluster, to ArgoCD pulling from this repo and applying changes on its own. Each environment's desired image tag now lives in its own values file (`values-dev.yaml`, `values-staging.yaml`, `values-production.yaml`), and ArgoCD keeps the cluster in sync with whatever those files say. dev updates automatically the moment a build finishes; staging and production are promoted by hand through a dedicated `promote.yml` workflow, and reviewing/merging the resulting pull request is what actually approves the change - no kubeconfig, security group access, or AWS credential is needed anywhere in the deploy pipeline anymore.

📄 [Full guide: setup, testing, and reasoning](./docs/v6-argocd.md)

## v7: Jenkins (alternative CI/CD pipeline)

A second EC2 instance, `jenkins-server`, runs a fully self-hosted Jenkins controller, configured entirely from code via JCasC - no manual setup wizard, no clicking through "Manage Jenkins" by hand. Deployment moves back to a push model: Jenkins builds and pushes the image, then deploys directly to dev, staging, and production with its own native approval gates, replacing `deploy.yml` and `promote.yml` entirely. GitHub Actions' role narrows to just `infra.yml` - provisioning and tearing down the AWS infrastructure itself. ArgoCD and the pull-based model from v6 remain fully intact on the `v6.0.0` tag.

📄 [Full guide: setup, testing, and reasoning](./docs/v7-jenkins.md)

## License

MIT, see [`LICENSE`](./LICENSE).