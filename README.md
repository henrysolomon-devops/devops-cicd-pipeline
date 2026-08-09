# DevOps CI/CD Pipeline

A complete, end-to-end DevOps CI/CD pipeline built incrementally, one tool at a time. Each version adds exactly one new concept to an already-working system, starting from containerizing a simple app and working up to Kubernetes, Infrastructure as Code, GitOps, CI/CD, observability, networking, and managed Kubernetes on AWS.

The goal isn't just to run the commands, but to understand why each tool is used. See [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) for the full roadmap, conventions, and reasoning behind every decision. Each version below also has its own detailed guide under [`docs/`](./docs), covering setup, testing, and the reasoning behind that version specifically.

**Looking for a specific tool rather than the latest version?** This repo has been through three different infrastructure tools, each with its own best, most-polished checkpoint:
- **Terraform**: the `v8.1.0` tag is the last and most complete version built on Terraform, before v9 replaced it with CloudFormation.
- **CloudFormation + a hand-built EC2/k3s server**: the `v9.0.0` tag - CloudFormation managing a single EC2 instance and a hand-written Application Load Balancer, before v10 moved onto EKS.
- **CloudFormation + Amazon EKS**: `main` / the `v10.0.0` tag - the current and final version, with a managed Kubernetes control plane, IRSA, and the AWS Load Balancer Controller.

Each tag is a fully working, independently tested checkpoint - none of them depend on anything from a later version.

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
| v8.0 | Prometheus + Grafana | Observability & monitoring | ✅ Done |
| v8.1 | Loki + Grafana Alloy + Alertmanager | Log aggregation & alerting | ✅ Done |
| v9.0 | Load Balancer + AWS CloudFormation | Networking, alternative IaC | ✅ Done |
| v10.0 | Migration to Amazon EKS | Managed Kubernetes, IRSA, AWS Load Balancer Controller | ✅ Done |

## Project structure

Each tool gets its own folder at the repo root, added as the version that introduces it gets built. The layout below shows the full planned structure; folders marked with a later version number don't exist yet.

    devops-cicd-pipeline/
    ├── app/            # Application source code (v1, Redis + Open-Meteo + /metrics added in v8, APP_URL_PREFIX added in v9)
    ├── docker/         # Dockerfile + .dockerignore (v1)
    ├── helm/           # Helm chart (v3, Redis/ServiceMonitor/dashboard templates added in v8, app-level alerting rules added in v8.1, NodePort + appUrlPrefix added in v9, Ingress + ClusterIP restored in v10)
    ├── .github/        # GitHub Actions workflows (v4, extended in v5.1, rewritten around CloudFormation in v9, rewritten around EKS in v10)
    ├── cloudformation/ # Infrastructure as Code (v9, EKS cluster + IRSA stacks replace the EC2/ALB stacks in v10 - recoverable from the v9.0.0 tag)
    ├── argocd/         # GitOps application definitions (v6, recovered in v8 after v7's detour)
    ├── monitoring/     # Prometheus + Grafana config (v8, Loki/Alloy/Alertmanager config added in v8.1, Grafana NodePort added in v9, IRSA + CloudWatch datasource added in v10)
    └── docs/           # Detailed per-version guides (setup, testing, reasoning)

`ansible/` and `terraform/`, used from v5 through v9, were removed entirely in v10 - EKS Managed Node Groups bootstrap themselves automatically, and CloudFormation had already replaced Terraform back in v9. Both remain fully recoverable from earlier tags.

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

A second EC2 instance, `jenkins-server`, ran a fully self-hosted Jenkins controller, configured entirely from code via JCasC - no manual setup wizard, no clicking through "Manage Jenkins" by hand. Deployment moved back to a push model: Jenkins built and pushed the image, then deployed directly to dev, staging, and production with its own native approval gates. This was a deliberate, self-contained detour to demonstrate an alternative CI tool; v8 reverted to v6's GitOps architecture as the base going forward. Jenkins and its server remain fully intact on the `v7.0.0` tag.

📄 [Full guide: setup, testing, and reasoning](./docs/v7-jenkins.md)

## v8: Prometheus + Grafana (Observability & Monitoring)

Real observability, for the first time: `kube-prometheus-stack` (Prometheus, Grafana, node-exporter, kube-state-metrics) is installed automatically as part of `infra.yml`, right alongside the ArgoCD setup restored from v6. The app now exposes custom metrics at `/metrics` - request rate and latency for every route, plus call duration, error rate, and cache hit/miss counters for a new Los Angeles weather feature (a real Open-Meteo API call, cached briefly in a lightweight per-namespace Redis with no persistent storage). A custom Grafana dashboard, defined as a JSON file in the repo rather than clicked together by hand, covers all of it with an environment switcher for dev/staging/production. Grafana itself runs with no login screen, since access is already restricted at the network level to a single IP.

📄 [Full guide: setup, testing, and reasoning](./docs/v8-observability.md)

## v8.1: Loki + Grafana Alloy + Alertmanager (Log Aggregation & Alerting)

Adds log aggregation and alerting on top of v8's metrics-only observability stack. Grafana Alloy (the current standard, replacing the now end-of-life Promtail) collects logs from every Pod across every namespace and ships them to Loki, which stores them in a dedicated S3 bucket so log history survives a `terraform destroy`/`apply` cycle the same way Terraform's own state already does - accessed via an IAM Instance Profile on the EC2 instance, since k3s has no IRSA. Alertmanager, bundled with `kube-prometheus-stack` since v8 but left disabled until now, routes alerts to two separate Slack channels (`#alerts-infra` and `#alerts-app`) based on a `team` label carried by every alerting rule. A new "Live Logs" panel on the existing app dashboard uses the same environment switcher already in place for metrics.

📄 [Full guide: setup, testing, and reasoning](./docs/v8.1-observability-logging.md)

## v9: Load Balancer + AWS CloudFormation

Terraform is replaced entirely by three CloudFormation stacks (network, compute, load balancer), connected through cross-stack `Fn::ImportValue` references rather than Terraform's module system - a direct comparison between a multi-cloud IaC tool and AWS's own native one. An Application Load Balancer now sits in front of all three environments, routing by URL path (`/dev`, `/staging`, `/production`) instead of by port, which meant moving each environment's Service from `LoadBalancer` to `NodePort` with an explicitly pinned port so the ALB's Target Groups always know exactly where to reach it. The app itself gained an `APP_URL_PREFIX`, while `/health` and `/metrics` deliberately stayed unprefixed, since Kubernetes' probes and Prometheus' scraper both reach those directly, never through the ALB. The app port is no longer reachable from outside at all - the ALB is now the only way in.

📄 [Full guide: setup, testing, and reasoning](./docs/v9-cloudformation-loadbalancer.md)

## v10: Migration to Amazon EKS

The single, manually-managed k3s server from v5 through v9 is replaced by Amazon EKS - a real, managed, multi-AZ Kubernetes control plane. Two CloudFormation stacks (`eks-cluster-stack.yaml`, `iam-irsa-stack.yaml`) replace the hand-built EC2 instance and ALB stacks from v9; `ansible/` is gone entirely, since EKS Managed Node Groups bootstrap themselves. IRSA replaces the IAM Instance Profile workaround Loki has used since v8.1, giving individual Pods (Loki, Grafana, the AWS Load Balancer Controller) their own scoped AWS identities instead of sharing one instance-wide identity. The hand-written ALB from v9 is replaced by a native Kubernetes `Ingress`, automatically turned into a real, shared ALB by the AWS Load Balancer Controller - the same "one address, three paths" model as before, now built and managed by AWS rather than by hand in CloudFormation. Grafana gained a CloudWatch datasource, used for exactly one thing: EKS's own control plane logs, which exist nowhere else since the control plane itself runs entirely outside this account's visibility.

📄 [Full guide: setup, testing, and reasoning](./docs/v10-eks-migration.md)

## License

MIT, see [`LICENSE`](./LICENSE).
