# v6: ArgoCD (GitOps-based Continuous Deployment)

**Concept demonstrated:** GitOps - pull-based, Git-as-source-of-truth deployment

## Why ArgoCD?

Through v5.1, `deploy.yml` did the deploying itself: it held a `KUBECONFIG_B64`
secret, opened a security group hole for its own IP, and ran `helm upgrade`
directly against the cluster. That's a **push** model - an outside system
(GitHub Actions) reaches into the cluster and changes it.

GitOps flips that direction. An agent that lives **inside** the cluster
(ArgoCD) continuously watches a Git repository and pulls in whatever it finds
there. Nothing outside the cluster ever needs write access to it again - not
a kubeconfig, not a security group rule, not an AWS credential. The only
thing that changes is Git itself.

## Why this matters beyond "it's more secure"

- **No external credential can leak the cluster**, because no external
  system holds one anymore.
- **Drift detection is automatic.** ArgoCD constantly compares what's
  actually running against what Git says should be running, and flags any
  difference (`OutOfSync`) - the same class of problem that caused a real
  bug back in v5.1 (a stale `SECURITY_GROUP_ID` variable).
- **Self-healing at the config level.** If someone edits something in the
  cluster by hand, ArgoCD notices the drift and can bring it back in line
  with Git on its own.

## Key concepts

- **Application**: an ArgoCD custom resource that tells it what to manage -
  which Git repo, which path, which values file, which namespace to deploy
  into, and whether to sync automatically or wait to be told.
- **Sync**: the act of ArgoCD reconciling the cluster with what's in Git.
  `automated` sync policy means it does this the moment it notices a
  difference, with no extra click required.
- **Push vs. pull**: push means an external system writes into the cluster;
  pull means the cluster reads from an external source (Git) on its own.
  GitOps is pull-based.

## Why approval no longer lives in GitHub Environments

Previously, staging and production each had a GitHub Environment with a
required reviewer - approval meant clicking "Review deployments" in the
Actions UI. That gate doesn't fit a pull model well: since ArgoCD (not
Actions) is the one applying changes, there's nothing left for an Actions
environment gate to actually protect.

Instead, approval moved to where the real decision already lives: **merging
a pull request**. Every environment's desired image tag is now stored, in
plain text, in its own values file (`values-dev.yaml`, `values-staging.yaml`,
`values-production.yaml`). Promoting a tag means proposing a one-line change
to that file through a PR; merging the PR *is* the approval. The diff is
real and reviewable, not a blind click.

dev is the one exception - it has no approval gate by design, so its PR is
opened and merged automatically by the same job that built the image.

## What changed from v5.1

- `argocd/dev-application.yaml`, `argocd/staging-application.yaml`,
  `argocd/production-application.yaml` (new): one `Application` per
  environment, each pointing at `helm/devops-pipeline` with its own values
  file, `syncPolicy.automated` enabled on all three
- `.github/workflows/infra.yml`: now also creates the `argocd` namespace,
  installs ArgoCD (pinned to `v2.13.2`, not `stable`), waits for it to come
  up, and registers the three `Application` manifests - all of this has to
  live here, not run by hand once, since a fresh server from `terraform
  destroy`/`apply` starts with none of it
- `.github/workflows/deploy.yml`: rewritten. It only builds and pushes the
  image now - no kubeconfig, no security group access, no AWS credentials.
  Its only cluster-adjacent job (`deploy-dev`) opens a PR bumping
  `values-dev.yaml` and merges it immediately, since dev has no approval
  gate. A `paths-ignore` list keeps the three values files from
  re-triggering this workflow when they're changed by automation
- `.github/workflows/promote.yml` (new): manual-only (`workflow_dispatch`),
  promotes whatever tag is currently running in dev to staging, or
  currently running in staging to production. Opens a PR and stops -
  reviewing and merging that PR is the actual approval
- `helm/devops-pipeline/values-dev.yaml`, `values-staging.yaml`,
  `values-production.yaml`: each now has an explicit `image.tag` field.
  Before v6, the tag was only ever passed in with `helm --set` at deploy
  time and never lived in a file; GitOps needs it to actually be in Git for
  ArgoCD to read
- `helm/devops-pipeline/templates/deployment.yaml`: stopped overriding the
  container's `APP_VERSION` environment variable with `image.tag` (the
  commit SHA). The image already has the correct human-readable version
  baked in via the Dockerfile - this override was silently replacing it
- `VERSION` (new, repo root): a plain-text semantic version (e.g. `6.0.0`),
  read by `deploy.yml` and passed into the Docker build as `APP_VERSION`,
  kept separate from the commit-SHA image tag used in ghcr.io
- `docker/Dockerfile`: accepts `APP_VERSION` as a build arg and bakes it in
  as an `ENV`, so the version shown on the dashboard no longer depends on
  anything set at deploy time
- `terraform/compute.tf`: bumped the EC2 instance from `t3.small` to
  `t3.medium`. ArgoCD's own components (server, repo-server,
  application-controller, dex, redis, and more) run alongside k3s and the
  app Pods, and `t3.small`'s 2GB of RAM wasn't enough room for all of it at
  once

## Setup

Nothing to run by hand here - ArgoCD installing itself, and the three
`Application` manifests getting registered, all happens automatically as
part of `infra.yml`'s `apply` path. Anyone forking this repo just needs to
run that workflow once; there's no separate manual install step.

## Testing

For anyone running this from a fork, this is the sequence:

```bash
# 1. Bring the server up (also installs ArgoCD and registers the
#    three Applications as part of the same run)
# Run infra.yml with action: apply
```

**Ran into a real problem here:** with `t3.small`, the server ran out of
memory once ArgoCD's components were running alongside k3s and the app
Pods - `load average` over 10, and even `kubectl` itself started timing
out. Bumped the instance to `t3.medium` (see `terraform/compute.tf`) 

```bash
# 2. Trigger a normal build + dev deploy
# Push any app change to main, or run deploy.yml by hand
# Approve infra-check when it pauses, then wait for deploy-dev to
# open and auto-merge its own PR
```

**dev**, confirmed in a browser and with curl:

```bash
curl http://<server-ip>:5000/api/status
# {"environment": "dev", "version": "6.0.0", "hostname": "devops-pipeline-dev-..."}
```

```bash
# 3. Promote the tested tag to staging
# Run the Promote workflow with environment: staging
# Review the diff on the PR it opens, then merge it by hand
```

**staging**, confirmed the same way on its own port:

```bash
kubectl get pods -n staging
# 2 Pods Running, matching replicaCount: 2 in values-staging.yaml

curl http://<server-ip>:5001/api/status
# {"environment": "staging", "version": "6.0.0", "hostname": "devops-pipeline-staging-..."}
```

```bash
# 4. Promote the same tag to production
# Run the Promote workflow with environment: production
# Review and merge that PR too
```

**production**, confirmed on its own port:

```bash
curl http://<server-ip>:5002/api/status
# {"environment": "production", "version": "6.0.0", "hostname": "devops-pipeline-production-..."}
```

Also confirmed that ArgoCD actually shows all three as synced and healthy:

```bash
kubectl get applications -n argocd
# NAME                         SYNC STATUS   HEALTH STATUS
# devops-pipeline-dev          Synced        Healthy
# devops-pipeline-staging      Synced        Healthy
# devops-pipeline-production   Synced        Healthy
```

## Testing self-heal

The last thing to confirm was `selfHeal: true`, set on all three
`Application` manifests since the beginning but never actually exercised
until now. The idea: manually change something in the cluster, bypassing
Git entirely, and see whether ArgoCD notices and reverts it on its own.

**dev** - manually scaled up to 3 replicas (Git says 1):

```bash
kubectl scale deployment devops-pipeline-dev -n dev --replicas=3
```

Within seconds, the two extra Pods were taken back down on their own,
with no command from me:

```bash
kubectl get pods -n dev
# NAME                                   READY   STATUS    RESTARTS   AGE
# devops-pipeline-dev-...   1/1     Running   0          16m
```

**staging** - manually scaled up to 5 replicas (Git says 2):

```bash
kubectl scale deployment devops-pipeline-staging -n staging --replicas=5
```

Same result - the three extra Pods were terminated automatically, back
down to the two Git actually calls for.

**production** - manually scaled down to 1 replica (Git says 3):

```bash
kubectl scale deployment devops-pipeline-production -n production --replicas=1
```

This time ArgoCD went the other direction - it brought two more Pods
*back up* to restore the 3 replicas Git says production should have:

```bash
kubectl get pods -n production
# NAME                                          READY   STATUS    RESTARTS   AGE
# devops-pipeline-production-...   1/1     Running   0          15m
# devops-pipeline-production-...   1/1     Running   0          20s
# devops-pipeline-production-...   1/1     Running   0          10s
```

All three `Application`s stayed `Synced` and `Healthy` throughout - ArgoCD
handled every one of these manual changes on its own, in both directions
(scaling extra Pods down, and bringing missing ones back up), without
anyone touching Git or the cluster again after the initial manual edit.
