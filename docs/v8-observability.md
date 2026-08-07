# v8: Prometheus + Grafana (Observability & Monitoring)

**Concept demonstrated:** Observability and monitoring

## Why Prometheus and Grafana?

Through v7, the only way to know whether the system was actually working
was to `curl` an endpoint and see if it answered. That tells you the app
is up, but nothing about *how* it's behaving underneath - how much load
it's under, how slow requests are getting, whether a dependency is
struggling. Prometheus is a time-series database that continuously
scrapes metrics from every part of the stack (CPU, memory, Pod status,
and now the app itself), and Grafana turns those metrics into dashboards
you can actually read. This is the first version where the project has
real observability, not just a health check.

## Reverting v7's architecture

v7 replaced ArgoCD with Jenkins to demonstrate a push-based CI/CD model
as a deliberate learning exercise - but architecturally, the GitOps
model from v6 was the stronger design. v8 goes back to v6's
architecture (ArgoCD, a single server) before adding observability on
top of it. Nothing from v7 is lost: the full Jenkins setup is still
recoverable from the `v7.0.0` tag if a future version wants to revisit
it, and a few genuinely useful fixes that had nothing to do with Jenkins
specifically (the Ansible SSH multiplexing fix in `ansible.cfg`) were
kept rather than thrown away.

## Key concepts

- **ServiceMonitor**: a Custom Resource (from the Prometheus Operator,
  installed as part of `kube-prometheus-stack`) that tells Prometheus
  where to scrape metrics from. Without one, Prometheus only ever sees
  built-in Kubernetes/node metrics - it has no idea an app's `/metrics`
  endpoint even exists.
- **Counter vs. Histogram**: a Counter only ever goes up (used here for
  request counts and errors); a Histogram buckets observed values (used
  here for request duration), which is what lets Grafana calculate a
  percentile like p95 instead of just an average.
- **Dashboard as code**: instead of clicking a dashboard by
  hand in the Grafana UI (which would be wiped on every `terraform
  destroy`), the dashboard is a JSON file in the repo, loaded
  automatically into Grafana through a labeled ConfigMap and a sidecar
  container that watches for it.

## What's included

- **`kube-prometheus-stack`**: installed by `infra.yml`, into a new
  `monitoring` namespace. Bundles Prometheus, Grafana, `node-exporter`
  (hardware metrics per node), and `kube-state-metrics` (Kubernetes
  object state, like Pod counts). Alertmanager is explicitly disabled -
  see "What's next" below for why.
- **A Redis cache, per namespace**: a small, single-replica Deployment
  with no PersistentVolume, sitting in front of a new weather lookup
  (see below). Deliberately left out of persistent storage entirely, to
  keep this version focused on one new concept rather than two.
- **A Los Angeles weather feature**: a real, unauthenticated third-party
  dependency (Open-Meteo) was added to the app specifically to give the
  observability stack something realistic to measure - external call
  latency, an error rate, and a cache hit/miss ratio - rather than
  inventing a fake `/api/simulate` endpoint with no real purpose. Shown
  on the dashboard and in `/api/status`, cached in Redis with a short
  TTL.
- **Custom app metrics**, exposed at `/metrics`: request count and
  latency for every route, external API call duration and errors
  (scoped to `api="open-meteo"`), and cache hit/miss counters.
- **A custom Grafana dashboard**, "devops-pipeline: App Metrics (v8)",
  with six panels (request rate, p95 latency, status codes, Open-Meteo
  call duration, Open-Meteo error rate, and Redis cache hit ratio) and
  an `$environment` dropdown to switch between `dev`/`staging`/
  `production` without needing three separate dashboards.

## What changed from v7

- `jenkins/`, `Jenkinsfile`, `ansible/install-jenkins.yml`,
  `ansible/deploy-jenkins.sh` (removed): Jenkins and everything specific
  to it. Fully recoverable from the `v7.0.0` tag.
- `argocd/*.yaml` (restored from `v6.0.0`, unchanged): the three
  per-environment `Application` manifests.
- `.github/workflows/deploy.yml`, `promote.yml` (restored from
  `v6.0.0`, unchanged): back to the GitOps model - these workflows only
  ever bump an image tag and open a pull request, they never touch the
  cluster directly.
- `.github/workflows/infra.yml`: Jenkins provisioning removed;
  `kube-prometheus-stack` installation added, deliberately *before*
  ArgoCD, since the app chart's own `ServiceMonitor` needs that CRD to
  already exist by the time ArgoCD syncs it.
- `monitoring/values.yaml` (new): the single source of truth for how
  Prometheus and Grafana are configured - cross-namespace
  ServiceMonitor and dashboard discovery, Grafana's LoadBalancer
  Service, resource limits, and Alertmanager disabled.
- `helm/devops-pipeline/templates/redis-deployment.yaml`,
  `redis-service.yaml`, `servicemonitor.yaml`,
  `grafana-dashboard-configmap.yaml` (new): Redis, the scrape
  registration, and the dashboard ConfigMap (only enabled in
  `values-dev.yaml`, since the dashboard only needs to be registered
  once, not once per namespace).
- `helm/devops-pipeline/dashboards/app-metrics.json` (new): the
  dashboard definition itself.
- `app/app.py`, `requirements.txt`, `templates/dashboard.html`: Redis
  and Open-Meteo integration, Prometheus instrumentation, and the new
  `/metrics` endpoint.
- `terraform/compute.tf`: instance type bumped from `t3.medium` to
  `t3.large`, and an explicit 30GB root volume added (see "Testing"
  below for why).
- `terraform/security.tf`: a permanent ingress rule added for
  Grafana's port (3000), scoped to my own IP only, same as every other
  permanent rule on this security group.

## Setup

Nothing to run by hand. `kube-prometheus-stack`, ArgoCD, and the three
`Application` registrations all happen automatically as part of
`infra.yml`'s `apply` path, the same as v6. Anyone forking this repo
just needs to run that workflow once.

## Testing

**1. Bring up the infrastructure:**

```
# infra.yml -> apply
```

This provisions the server (`t3.large`, with an explicit 30GB root
volume - large enough to hold every image for k3s, ArgoCD, and the full
`kube-prometheus-stack` at once), installs k3s, installs
`kube-prometheus-stack` into the `monitoring` namespace, installs
ArgoCD, and registers the three `Application` manifests. No manual
steps after this.

**2. Confirm dev deployed automatically:**

```
curl http://<server-ip>:5000/api/status
```

```json
{
  "environment": "dev",
  "version": "8.0.0",
  "weather": {"condition": "Clear sky", "source": "live", "temperature_c": 27.1}
}
```

**3. Promote to staging, then production:**

```
# promote.yml -> environment: staging
```

Review and merge the pull request it opens, then confirm:

```
curl http://<server-ip>:5001/api/status
```

Repeat for production:

```
# promote.yml -> environment: production
```

```
curl http://<server-ip>:5002/api/status
```

**4. Open Grafana:**

```
http://<server-ip>:3000
```

No login screen - access is already restricted to a single IP at the
security group level (see `terraform/security.tf`), so an additional
login layer would just be friction with no real security benefit.

**5. Open the dashboard:**

Go to **Dashboards** and open **"devops-pipeline: App Metrics (v8)"**
(or filter by the `v8` tag). Use the **`$environment`** dropdown at the
top to switch between `dev`, `staging`, and `production` - each shows
its own independent data, confirming the per-namespace label filtering
works correctly.

**6. Generate some traffic to see the panels move:**

```bash
for i in $(seq 1 20); do curl -s http://<server-ip>:5002/api/status > /dev/null; sleep 2; done
```

With the Redis cache TTL at 60 seconds, the first request in that loop
should register as a cache **miss** (a real call to Open-Meteo), and the
remaining ones as **hits** - visible on the **Redis Cache Hit Ratio**
panel, along with a corresponding spike on **Request Rate by Endpoint**.

**7. (Optional) Confirm Prometheus is scraping directly:**

```
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Visit `http://localhost:9090/targets` and look for three targets named
`serviceMonitor/<namespace>/devops-pipeline-<namespace>/0` - one per
environment, all `UP`.

**8. Confirm self-healing still holds** (same check as every version
since v2, still true now that ArgoCD is managing the Deployment):

```
kubectl delete pod <pod-name> -n production
kubectl get pods -n production
```

A new Pod replaces it automatically, and ArgoCD's own `selfHeal` keeps
the replica count matching whatever `values-production.yaml` declares.

## What's next

**v8.1** will add **Loki + Grafana Alloy** for log aggregation, plus
**Alertmanager** for alerting - both were deliberately left out of v8.
Alerting on its own has limited value without a way to jump straight
from an alert to the logs that explain it, so the two are being built
together rather than Alertmanager going in alone now. Grafana Alloy is
used rather than the older Promtail, which reached end-of-life on March
2, 2026.
