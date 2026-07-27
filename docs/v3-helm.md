# v3: Helm chart

**Concept demonstrated:** Package management for Kubernetes

## Why Helm?

In v2, the same Deployment and Service manifests were applied separately into three namespaces with plain `kubectl apply`. That works, but it has a few real limitations: there's no clean way to give each environment different settings (like a different replica count), no built-in versioning for the deployment itself, and updating anything means editing raw YAML by hand in three places.

Helm is a package manager for Kubernetes. You write your Kubernetes resources as templates (with placeholders instead of fixed values), keep the actual values in separate `values.yaml` files, and Helm fills in the templates and tracks every install/upgrade as a versioned release that can be rolled back.

## Key concepts

- **Chart** : a packaged collection of Kubernetes templates, similar to an installable package
- **Template** : a YAML file with placeholders (e.g. `{{ .Values.replicaCount }}`) instead of hardcoded values
- **Values** : the actual values used to fill in a template. This project has a base `values.yaml` plus one override file per environment (`values-dev.yaml`, `values-staging.yaml`, `values-production.yaml`)
- **Release** : a named, versioned installation of a chart. Every `helm install` or `helm upgrade` creates a new revision that Helm keeps track of

## What changed from v2

The `k8s/deployment.yaml` and `k8s/service.yaml` files from v2 were rewritten as Helm templates under `helm/devops-pipeline/templates/`. The `k8s/` folder itself was removed from the repo since it's no longer used. See [`docs/v2-kubernetes.md`](./v2-kubernetes.md) for how things worked before this change.

Per-environment differences are now handled cleanly through values files instead of duplicating YAML. For example, replica count now differs by environment:

| Environment | replicaCount |
|---|---|
| dev | 1 |
| staging | 2 |
| production | 3 |

## Setup

```bash
# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

# Scaffold the chart (only done once, kept here for reference)
helm create helm/devops-pipeline
```

## Installing to each namespace

```bash
helm install devops-dev helm/devops-pipeline -f helm/devops-pipeline/values-dev.yaml -n dev
helm install devops-staging helm/devops-pipeline -f helm/devops-pipeline/values-staging.yaml -n staging
helm install devops-production helm/devops-pipeline -f helm/devops-pipeline/values-production.yaml -n production
```

## Testing

```bash
kubectl get pods -n dev
kubectl port-forward <pod-name> 8080:5000 -n dev
```

Visit `http://localhost:8080`, `http://localhost:8080/api/status`, and `http://localhost:8080/health`. All three matched the same behavior verified in v1 and v2.

## Upgrade and rollback

To show the actual benefit of Helm over plain `kubectl apply`, a real change was tested end to end:

```bash
# Bump replicaCount in dev from 1 to 2
helm upgrade devops-dev helm/devops-pipeline -f helm/devops-pipeline/values-dev.yaml --set replicaCount=2 -n dev

# Check the revision history
helm history devops-dev -n dev

# Roll back to the previous revision
helm rollback devops-dev 1 -n dev
```

Helm kept a full history of both the install and the upgrade, and rolling back required nothing more than the target revision number. No manual YAML editing and no need to remember what the previous state was.
