# v7: Jenkins (alternative CI/CD pipeline)

**Concept demonstrated:** Alternative CI tooling, and a second look at push-based deployment

## Why Jenkins?

Every version so far has used GitHub Actions - a CI/CD service that GitHub hosts and
runs for you. Jenkins is a different kind of tool entirely: a self-hosted, plugin-based
automation server that you install, run, and fully own yourself. It's one of the
oldest and most widely used CI/CD tools in the industry, especially in larger or
older organizations that built their pipelines before hosted CI existed.

Demonstrating Jenkins alongside GitHub Actions shows fluency with more than one
CI/CD paradigm, not just one vendor's product. The two tools solve the same basic
problem - "run these steps automatically when code changes" - but come from very
different philosophies: hosted vs. self-managed, YAML vs. Groovy, tightly coupled
to one Git provider vs. usable with any of them.

## Two servers, not one

This version introduces a second EC2 instance, `jenkins-server`, alongside the
existing `app-server` from v5 onward. Jenkins runs entirely on its own box; `app-server`
still only runs k3s and the three environment namespaces.

Splitting them apart mirrors how real infrastructure is usually built: the system
that builds and drives deployments is kept separate from the system being deployed
to. It also keeps each server's security group honest - `jenkins-server`'s security
group only opens SSH and the Jenkins UI port, `app-server`'s only opens what the
app and k3s actually need. Neither server ends up with ports open that it doesn't
use.

## Back to a push model - and why that's fine

v6 moved deployment to a pull model: ArgoCD, living inside the cluster, watched
Git and applied changes on its own. This version deliberately moves back to a
push model - Jenkins runs `helm upgrade` directly, the same way `deploy.yml` did
back in v5.1.

That's not a step backward so much as a demonstration of both. Push and pull are
both legitimate, widely used patterns in real DevOps work, and which one fits
depends on the organization - some teams standardize on GitOps, plenty of others
still run centralized CI systems that deploy directly. Showing both, deliberately,
is more useful for a portfolio than picking one and treating it as the only right
answer. Nothing about v6 was wrong; ArgoCD and the three `Application` manifests
are still fully intact on the `v6.0.0` tag if a future version wants to go back to
a GitOps model.

Because of this shift, `deploy.yml` and `promote.yml` - the two GitHub Actions
workflows that handled building images and promoting them through environments -
are removed entirely in this version. Jenkins now owns that whole responsibility
end to end, from build through production. `infra.yml` is the only GitHub Actions
workflow left, and its job stays exactly what it's always been: standing up and
tearing down the AWS infrastructure itself.

## Jenkins Configuration as Code (JCasC)

Jenkins is configured entirely from files in the repo, not by clicking through
its setup wizard or its "Manage Jenkins" screens by hand. `jenkins/jenkins.yaml`
defines everything: the credential Jenkins needs, the pipeline job itself, and
Jenkins' own basic settings. `jenkins/plugins.txt` lists the plugins that
configuration depends on.

This matters for the same reason Ansible mattered for k3s back in v5, and JCasC
mattered for ArgoCD in v6: this server gets destroyed and rebuilt from scratch on
every `destroy`/`apply` cycle, so nothing about its setup can depend on a human
remembering to click the same sequence of buttons again. Jenkins reads this
configuration itself the moment it starts up.

One consequence worth calling out: `jenkins.yaml` explicitly turns Jenkins'
login screen off (`securityRealm: None`, `authorizationStrategy: unsecured`).
That's a deliberate simplification, not an oversight - `jenkins-server`'s security
group only lets my own IP reach port 8080 at all, so anyone who can reach the
login screen in the first place is already me. This is a reasonable trade-off for
a personal, throwaway learning server; it would not be for anything shared or
long-lived.

## No separate Jenkins agent

Jenkins draws a distinction between the **controller** (the server running Jenkins
itself) and an **agent** (a machine, possibly a different one, that actually
executes pipeline steps). This version deliberately uses no separate agent - every
pipeline stage runs on the controller's own built-in node.

The alternative would have been installing a Jenkins agent process on `app-server`
so pipeline steps could run there directly. That's unnecessary here: `jenkins-server`
already has everything it needs (Docker for building images, `kubectl` and `helm`
for deploying) installed locally, and it reaches the k3s API on `app-server`
directly over the network using a kubeconfig, the same way any remote client
would. Adding a second Jenkins process on `app-server` would only add moving parts
without adding capability.

Since both servers live in the same VPC, that kubeconfig points at `app-server`'s
**private** IP rather than its public one - the two servers can already reach each
other directly over the internal network, so there's no reason to route that
traffic out to the internet and back.

## What changed from v6

- `terraform/compute.tf`: renamed the original server resource from `server` to
  `app_server` for clarity now that a second server exists, and added
  `aws_instance.jenkins_server` plus its own Elastic IP
- `terraform/security.tf`: renamed the original security group to match
  (`app_server`), added a new security group for `jenkins_server` (SSH and the
  Jenkins UI port, only from my own IP), and added a standing rule letting
  `jenkins_server` reach `app_server`'s k3s API - scoped to `jenkins_server`'s own
  security group rather than an IP, so access follows the instance itself
- `terraform/outputs.tf`: outputs renamed to match, plus a new
  `app_server_private_ip` output used to build Jenkins' kubeconfig
- `ansible/install-jenkins.yml` (new): installs Java, Docker, `kubectl`, `helm`,
  and Jenkins itself, copies the app server's kubeconfig into place, and points
  Jenkins at its JCasC configuration
- `ansible/deploy-jenkins.sh` (new): mirrors `deploy-k3s.sh` - reads the Jenkins
  server's IP from Terraform and runs the playbook against it
- `jenkins/jenkins.yaml`, `jenkins/plugins.txt` (new): the JCasC configuration and
  the plugin list it depends on
- `Jenkinsfile` (new, repo root): the pipeline itself - see below
- `.github/workflows/infra.yml`: no longer installs ArgoCD; now also provisions
  `jenkins-server` and hands it a kubeconfig and a GitHub Container Registry
  credential to run with
- `.github/workflows/deploy.yml`, `.github/workflows/promote.yml`: removed -
  Jenkins now owns the entire build-to-production pipeline
- `argocd/`: removed - no longer used now that deployment is push-based again.
  Fully recoverable from the `v6.0.0` tag if a later version returns to GitOps
- `VERSION`: bumped to `7.0.0`

## The pipeline itself

`Jenkinsfile` defines six stages, run in order:

1. **Read app version** - reads `VERSION`, the same human-readable string used
   since v6, kept separate from the commit SHA used as the actual image tag
2. **Build and push image** - builds the Docker image and pushes it to `ghcr.io`,
   authenticating with a GitHub PAT stored as a Jenkins credential (Jenkins has no
   access to GitHub Actions' automatic `GITHUB_TOKEN`, so it needs its own)
3. **Deploy to dev** - `helm upgrade --install`, no approval gate, same rule
   that's held since v4
4. **Approve staging** - Jenkins' native `input` step. The pipeline pauses here
   until someone clicks "Deploy" in the Jenkins UI - this replaces both the old
   GitHub Environment reviewer gate from v4/v5.1 and the PR-review gate from v6
5. **Deploy to staging**
6. **Approve production** / **Deploy to production** - the same pattern repeated
   for the last environment

Since the deployment model is push-based again, the image tag goes straight into
each `helm upgrade` call via `--set image.tag=<commit-sha>`, the same way it did
in v5.1 - it no longer needs to live in Git the way GitOps required in v6.

The pipeline job itself is triggered by polling: Jenkins checks the repository
for new commits on `main` every two minutes and starts a build automatically if
it finds one. Polling was chosen over a GitHub webhook on purpose - a webhook
would mean opening the security group to GitHub's IP ranges, while polling only
ever reaches outward, so the "only my own IP can reach in" rule never has to
change.

## Setup

Almost everything here is automatic. The one manual, one-time step is creating a
GitHub Personal Access Token scoped to `packages:write` (classic tokens only -
fine-grained tokens don't currently support the Packages scope), saved as the
repo secret `GHCR_PAT`. Running `infra.yml` with `apply` handles everything else:
both servers, k3s, the three namespaces, and a fully configured Jenkins with its
pipeline already registered.

## Testing

**Bringing the infrastructure up:**

```
# Run infra.yml with action: apply
```

This provisions both servers, installs k3s and the three namespaces on
`app-server`, and installs Jenkins (with its plugins, credential, and pipeline
job already registered via JCasC) on `jenkins-server`.

**Confirmed the Jenkins UI came up exactly as configured**, no login prompt and
the pipeline job already present:

```
http://<jenkins-server-ip>:8080
```

**Confirmed the automatic trigger actually works**, not just the initial
registration - pushed a real change to `main` and, without clicking anything,
watched Jenkins pick it up on its own within the two-minute polling window:

```
git push origin main
# no manual "Build Now" - Jenkins finds it on its own
```

**Watched the build run end to end**: the image built, pushed to `ghcr.io`
successfully using the JCasC-provided credential, and `dev` deployed
automatically with no approval needed.

```bash
curl http://<app-server-ip>:5000/api/status
# {"environment": "dev", "version": "7.0.0", ...}
```

**Confirmed the staging approval gate actually blocks**, not just displays -
the pipeline sat paused until "Deploy" was clicked in the Jenkins UI, then
continued:

```bash
curl http://<app-server-ip>:5001/api/status
# {"environment": "staging", "version": "7.0.0", ...}
```

**Same for production** - a second, separate approval click, then confirmed:

```bash
curl http://<app-server-ip>:5002/api/status
# {"environment": "production", "version": "7.0.0", ...}
```

All three environments showed the correct version, a real Pod hostname, and a
healthy status - the same checks used in every version since v1.

## What's next

v8 will introduce Prometheus and Grafana for observability and monitoring.
