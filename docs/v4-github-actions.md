# v4: GitHub Actions

**Concept demonstrated:** CI/CD pipeline

## Why GitHub Actions?

Through v3, every deployment was still manual: build the image, load it into kind, run `helm install`/`upgrade` by hand for each namespace. CI/CD automates this end to end, every push to `main` should build, test, and deploy without anyone re-typing the same commands.

## Why a self-hosted runner?

GitHub's default runners are temporary cloud VMs with no way to reach the local kind cluster, since kind only exists on this machine's Docker daemon. A **self-hosted runner** is a small agent installed directly on this Linux machine; it opens an outbound connection to GitHub and waits for jobs, so commands like `helm upgrade` run right here with direct access to kind, the same way `kubectl` and `helm` already do locally. This is the same pattern real companies use whenever their cluster is on-prem or behind a firewall.

Since this repo is public, GitHub's default protection (workflows from forked PRs don't run on self-hosted runners without a maintainer's approval) was left in place.

## Environments instead of branches

The original plan assumed three long-lived branches (`main`, `dev`, `staging`). In practice, this repo only ever uses `main` plus short-lived feature branches, so that mapping never applied.

Instead, this version uses **GitHub Environments** as a deployment control layer, independent of branches:

| Environment | Protection |
|---|---|
| dev | none - deploys immediately |
| staging | required reviewer |
| production | required reviewer |

Every deploy comes from the same commit on `main`; what differs is whether a human has to approve it first.

## What changed from v3

- `.github/workflows/deploy.yml` : the pipeline itself (see below)
- `app/app.py` : reads a new `APP_ENV` variable, same pattern as `APP_VERSION`
- `app/templates/dashboard.html` : shows the `Environment` field
- `helm/devops-pipeline/values.yaml` and each `values-<env>.yaml` : added `appEnv`
- `helm/devops-pipeline/templates/deployment.yaml` : added an `env:` block passing `APP_VERSION` and `APP_ENV` into the container
- ghcr.io is used for the first time here, kind never needed a registry since it loads images straight from the local Docker daemon, but a runner-driven pipeline needs somewhere to push to

## Setup

```bash
# Download and configure the runner (token comes from
# Settings -> Actions -> Runners -> New runner on GitHub)
mkdir ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L <url-from-github>
tar xzf ./actions-runner-linux-x64.tar.gz
sudo ./bin/installdependencies.sh
./config.sh --url https://github.com/henrysolomon-devops/devops-cicd-pipeline --token <token>

# Install and start it as a persistent service
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

Environments (`dev`, `staging`, `production`) and their required reviewers were created under **Settings -> Environments** on GitHub, not from the CLI.

A Personal Access Token needs the `workflow` scope in addition to `repo` to push changes to `.github/workflows/*` files, plain `repo` scope alone gets rejected.

## The workflow

`.github/workflows/deploy.yml` runs four jobs in order, using `needs:` so each one waits for the last to succeed:

1. **`build`** : checks out the code, logs in to ghcr.io with the automatic `GITHUB_TOKEN`, builds the image, tags it with the commit SHA (not `latest`), and pushes it
2. **`deploy-dev`** : `helm upgrade --install` against `dev`, using `values-dev.yaml`
3. **`deploy-staging`** : same, but pauses for manual approval first
4. **`deploy-production`** : pauses for its own separate approval, then deploys

## Testing

Since this workflow only triggers on push to `main`, and `main` is meant to always stay stable, the whole pipeline was tested on the feature branch first, without merging:

```yaml
# Temporarily added to deploy.yml's `on: push: branches:` list
# so a normal push would trigger it without needing main
  - feature/v4-github-actions
```

```bash
git add .github/workflows/deploy.yml
git commit -m "Temporarily trigger on feature branch push for testing"
git push origin feature/v4-github-actions
```

This ran the full pipeline end to end (build, push to ghcr.io, deploy to dev, pause for staging approval, pause for production approval) with zero risk to `main`. The temporary branch trigger was removed again once everything was confirmed working.

**Bug caught during testing:** v3's manual `helm install` commands used release names like `devops-dev`, `devops-staging`, `devops-production`, but this workflow's `helm upgrade --install` uses one consistent name, `devops-pipeline`, in every namespace. The mismatched names meant Helm didn't recognize the old releases as the same deployment, and installed a second, parallel release alongside each old one. Fixed by uninstalling the old releases by hand:

```bash
helm uninstall devops-dev -n dev
helm uninstall devops-staging -n staging
helm uninstall devops-production -n production
```

Verified in each namespace:

```bash
helm list -n dev
kubectl get pods -n dev
kubectl port-forward -n dev svc/devops-pipeline 8080:80
```

Visit `http://localhost:8080`. Confirmed one clean `devops-pipeline` release per namespace, the correct replica count (1 in dev, 2 in staging, 3 in production), and the dashboard's `Environment` field correctly showing `dev`, `staging`, or `production` in each case.

After testing, the temporary branch trigger was removed and the pipeline was run for real via an actual merge to `main`, confirming the real trigger path works the same as the test.
