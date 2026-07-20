# Project Plan - DevOps CI/CD Pipeline

## Goal

A complete, end-to-end DevOps CI/CD pipeline built incrementally (v1 → v9).
Each version adds exactly one new tool or concept to an already-working
system. The purpose is twofold:

1. **Learn the full DevOps toolchain hands-on**, understand *why* each
   tool is used, not just how to run the commands.
2. **Produce a real, working portfolio project**

## Roadmap

| Version | What's added | Concept demonstrated |
|---------|-------------|----------------------|
| v1.0 | Flask app + Docker + HTML dashboard | Containerization |
| v2.0 | Kubernetes (`kind` local cluster) + `dev`/`staging`/`production` namespaces | Orchestration, environment isolation |
| v3.0 | Helm chart | Package management for Kubernetes |
| v4.0 | GitHub Actions (branch-based deploy) | CI/CD pipeline |
| v5.0 | Terraform (EC2 + VPC) + Ansible (k3s install) | Infrastructure as Code, Configuration Management |
| v6.0 | ArgoCD | GitOps-based Continuous Deployment |
| v7.0 | Jenkins pipeline (alternative to Actions) | Alternative CI tooling |
| v8.0 | Prometheus + Grafana | Observability & monitoring |
| v9.0 | Load Balancer + AWS CloudFormation | Networking, alternative IaC |

## Environment Strategy (from v2 onward)

Three Kubernetes namespaces inside the same cluster, not separate
servers, to keep cost and complexity down:

```
dev          → early testing, updated on every push to the `dev` branch
staging      → pre-release testing, updated on push to `staging`
production   → live version, updated on merge to `main`
```

## Cost & Safety Rules

- The real AWS EC2 instance (from v5 onward) is **never left running**.
  Standard flow: `terraform apply` → test/record a demo → `terraform destroy`.
- No real AWS credentials are ever shared or stored in the repo.
  Terraform/CloudFormation code is written and explained;
  `apply`/`destroy` are run locally by the repo owner using their own
  AWS CLI credentials.

## Repository Conventions

- **Single repository** (`devops-cicd-pipeline`), not one repo per version,
  a unified commit history tells a clearer story than scattered repos.
- **Visibility:** Public.
- **License:** MIT.
- Folders (`k8s/`, `helm/`, `terraform/`, `ansible/`, `.github/workflows/`,
  `jenkins/`, `argocd/`, `monitoring/`) are added to the repo root as each
  version introduces them, not duplicated per version.
- **Docker images** are pushed to **GitHub Container Registry (ghcr.io)**,
  not Docker Hub, since it uses the default `GITHUB_TOKEN` in every
  Actions run, no separate registry credentials needed.
- **Branching:**
  ```
  main     → always stable, fully working
  dev      → active development (namespace: dev, from v2 on)
  staging  → pre-release testing (namespace: staging, from v2 on)
  ```
  Per version: branch off as `feature/vX-short-name`, merge to `main`,
  then tag:
  ```bash
  git tag vX.0.0
  git push origin main --tags
  ```
- **Branch protection on `main`:** pull requests are required before
  merging, no direct pushes to `main`, even for small fixes.
- A **GitHub Release** is published for every tag, summarizing what was
  added and why.
- Progress is tracked on a **GitHub Projects** board
  (`Backlog` → `In Progress` → `Done`).
- Repo **Description** and **Topics** are set from day one and expanded
  over time, not fixed at the start. Initial Topics (`devops`, `docker`,
  `kubernetes`, `terraform`, `cicd`, `argocd`) cover the core stack; as
  each new tool is introduced (Ansible, Jenkins, Prometheus, Grafana,
  AWS, etc.), Topics and Description are revisited to reflect the full
  toolset. See the **Per-Version Release Checklist** below.
- The repo is pinned on the profile.

## Per-Version Release Checklist

Before tagging a version as complete, go through this list:

- [ ] Update repo **Description** if the project's scope changed
- [ ] Review **Topics**, add any new tool introduced in this version
- [ ] Update **README** if setup/usage instructions changed
- [ ] Move the version's card to **Done** on the GitHub Projects board
- [ ] Create the **GitHub Release** with a short "what + why" summary
- [ ] Tag the version: `git tag vX.0.0 && git push origin main --tags`

## Working Principles

- Every version's documentation explains the *reasoning* behind each
  decision, the goal is understanding, not copy-pasting commands.
- Explanations assume no prior DevOps experience; each new tool or
  concept is introduced from first principles before it's used.
- All code is tested before being considered "done." Where a tool
  (Docker, Terraform, etc.) isn't available in the dev/test environment,
  that limitation is stated explicitly and a reasonable alternative
  verification is used instead (e.g., running the Flask app directly
  with Python instead of inside a container).
