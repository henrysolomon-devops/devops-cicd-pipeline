# v10: Migration to Amazon EKS

**Concept demonstrated:** Managed Kubernetes, IRSA, AWS Load Balancer Controller

## Why EKS?

Through v9, Kubernetes itself was k3s - a single control plane running as
a process on the same EC2 instance as everything else. That was the right
choice for v5 through v9, since a full `kubeadm` cluster and real
control-plane HA weren't the point of those versions. But it also meant
one real gap the whole project kept coming back to: if that one EC2
instance ever went down, the entire cluster - not just the app - went
down with it.

Amazon EKS closes that gap. AWS runs the control plane (api-server,
etcd, scheduler, controller-manager) as a managed, multi-AZ service -
it isn't visible in this account, isn't something this project SSHes
into, and isn't something a single instance failure can take down.
Moving to EKS also brings two other AWS-native pieces along with it,
deliberately bundled into this version rather than split out, since
they're direct consequences of the same underlying change:

- **IRSA** (IAM Roles for Service Accounts), replacing the IAM Instance
  Profile workaround Loki has used since v8.1 - k3s had no way to give
  an individual Pod its own AWS identity, only the whole EC2 instance.
- **The AWS Load Balancer Controller**, replacing the hand-written ALB
  from v9's CloudFormation. A native Kubernetes `Ingress` resource now
  describes the routing; the controller builds and manages the real ALB
  from it automatically.

## Key concepts

- **EKS Managed Node Group**: still real EC2 instances underneath, but
  AWS resolves the AMI, runs the node bootstrap process, and manages
  the Auto Scaling Group behind it - nothing here is SSH'd into or
  configured by Ansible the way k3s's node was.
- **IRSA**: an EKS cluster gets its own OIDC identity provider. A
  Kubernetes ServiceAccount, annotated with an IAM role ARN, lets a
  single Pod assume that role directly - real least-privilege at the
  Pod level, not just the instance level.
- **EKS Access Entries**: the modern, API-native replacement for
  hand-editing the `aws-auth` ConfigMap. Cluster administrative access
  is granted explicitly, per IAM principal, as a first-class part of
  the cluster's own CloudFormation resources.
- **Ingress + IngressGroup**: instead of one hand-written ALB with
  three Target Groups, each environment's Helm release now defines its
  own `Ingress`. All three carry the same `group.name` annotation,
  which is what makes the AWS Load Balancer Controller merge them into
  a single shared ALB - the same "one address, three paths" model v9
  built by hand, now built automatically.

## What's included

- **`cloudformation/eks-cluster-stack.yaml`**: the EKS control plane, a
  single-node Managed Node Group (t3.large), the cluster's OIDC
  provider, and Access Entries granting cluster-admin to both the
  GitHub Actions role and the AWS account root user (the latter for
  manual debugging via AWS CloudShell).
- **`cloudformation/iam-irsa-stack.yaml`**: three IRSA roles - Loki (S3
  access to its log bucket), the AWS Load Balancer Controller (ALB and
  Target Group management, using AWS's own published permission
  policy, embedded directly as a CloudFormation-managed resource), and
  Grafana (read-only CloudWatch access).
- **`helm/devops-pipeline/templates/ingress.yaml`**: the app's Ingress,
  annotated for the AWS Load Balancer Controller - path-based routing,
  a shared IngressGroup across all three environments, and target-type
  `ip` (routing directly to Pod IPs over the VPC CNI).
- **A CloudWatch datasource in Grafana**: EKS's control plane runs
  entirely outside this account's visibility, so control plane logs
  (api-server, audit, scheduler, controller-manager) exist nowhere
  except CloudWatch Logs. This is the one place CloudWatch is used -
  everything else (app metrics, logs, alerting) still runs on
  Prometheus, Loki, and Alertmanager exactly as it has since v8.1.

## What changed from v9

- `ansible/` removed entirely. EKS Managed Node Groups bootstrap nodes
  automatically - there's no SSH key, no playbook, and no manual node
  configuration step anywhere in this version.
- `cloudformation/compute-stack.yaml` and `cloudformation/loadbalancer-stack.yaml`
  removed, replaced by `eks-cluster-stack.yaml` and `iam-irsa-stack.yaml`.
  Fully recoverable from the `v9.0.0` tag.
- `cloudformation/network-stack.yaml`: both public subnets gained the
  `kubernetes.io/cluster/<name>: shared` and `kubernetes.io/role/elb: 1`
  tags EKS and the Load Balancer Controller both depend on to discover
  which subnets they're allowed to use.
- `helm/devops-pipeline/values.yaml` and each `values-<env>.yaml`:
  `service.type` reverted from `NodePort` back to `ClusterIP`, and the
  per-environment port overrides (5000/5001/5002) are gone entirely -
  with the Load Balancer Controller routing directly to Pod IPs, every
  environment can safely share the same port, since each lives in its
  own namespace regardless.
- `monitoring/loki-values.yaml`: credentials moved from an IAM Instance
  Profile to IRSA; the chart's default PersistentVolumeClaim for local
  WAL/index storage was replaced with an explicit ephemeral volume,
  since a fresh EKS cluster has no default StorageClass and nothing
  Loki caches locally is worth provisioning one just to persist.
- `monitoring/values.yaml`: Grafana's ServiceAccount gained an IRSA
  annotation for CloudWatch access, a CloudWatch datasource was added
  alongside the existing Loki one, and Grafana's NodePort moved from
  5010 to 30010 - EKS's fully-managed control plane doesn't allow
  widening the API server's NodePort range the way k3s's did.
- `.github/workflows/infra.yml`: rewritten around four CloudFormation
  stacks (network, EKS cluster, IRSA, plus the app/monitoring Helm
  installs), `aws eks update-kubeconfig` in place of a copied k3s
  kubeconfig, and a destroy path that removes every Ingress first so
  the Load Balancer Controller tears down the ALB before the network
  stack underneath it is deleted.
- `.github/workflows/deploy.yml`, `promote.yml`, and the three
  `argocd/*.yaml` Application manifests: unchanged. GitOps promotion is
  entirely independent of what the cluster itself is built on.

## Setup

Nothing to run by hand for most of this - the EKS cluster, IRSA roles,
AWS Load Balancer Controller, and the rest of the monitoring stack all
install automatically as part of `infra.yml`'s `apply` path.

Two one-time steps are required before the first `apply`:

**1. The `github-actions-eks-role`.** Created by hand, separate from
`github-actions-cloudformation-role` from v9, so the `v9.0.0` tag can
still be applied entirely on its own. Trust policy scoped to this
repo's `aws-infra` environment; permission policy covering
CloudFormation, EC2/ELB/Auto Scaling (both resist fine-grained scoping,
left broad per AWS's own guidance), EKS, scoped IAM role/policy
management, `iam:PassRole` restricted to `eks.amazonaws.com` and
`ec2.amazonaws.com`, `iam:CreateServiceLinkedRole` scoped to the EKS
and ELB service names, and SSM access scoped to `/devops-pipeline/*`.

**2. GitHub repo setup**: same environments, variables, and secrets as
v9 - nothing new was added.

## Testing

**1. Bring up the infrastructure:**

```
# infra.yml -> apply
```

This deploys all four stacks in order, writes a kubeconfig via
`aws eks update-kubeconfig`, installs the AWS Load Balancer Controller,
`kube-prometheus-stack`, Loki, Alloy, and ArgoCD, and registers the
three environment Applications.

**2. Confirm the cluster and node are healthy:**

```bash
aws eks update-kubeconfig --name devops-pipeline-eks --region us-east-1
kubectl get nodes
```

```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-0-1-136.ec2.internal   Ready    <none>   ...   v1.31.14-eks-...
```

**3. Confirm ArgoCD synced all three environments:**

```bash
kubectl get applications -n argocd
```

```
NAME                         SYNC STATUS   HEALTH STATUS
devops-pipeline-dev          Synced        Healthy
devops-pipeline-production   Synced        Healthy
devops-pipeline-staging      Synced        Healthy
```

**4. Confirm the shared ALB and path-based routing:**

```bash
kubectl get ingress -A
```

All three Ingress resources should show the exact same `ADDRESS` -
confirmation that the shared `group.name` merged them into one ALB.

```bash
ALB=<the-address-from-above>
curl -L http://$ALB/dev/
curl -L http://$ALB/staging/
curl -L http://$ALB/production/
```

Each should return the dashboard HTML, with its own `Environment` and
`URL prefix` values shown correctly.

**5. Confirm Grafana, on its new port:**

```
http://<node-public-ip>:30010
```

Open **Dashboards → devops-pipeline: App Metrics**, confirm the
`$environment` dropdown switches correctly between all three
namespaces, and that the Live Logs panel streams real entries.

**6. Confirm the CloudWatch datasource:**

**Connections → Data sources → CloudWatch → Save & test** should report
both the metrics and logs APIs queried successfully - confirmation that
IRSA is granting Grafana's Pod real, scoped AWS credentials with no
access key involved anywhere.

**7. Confirm self-healing still holds**, the same check every version
since v2 has used, now via ArgoCD's `selfHeal`:

```bash
kubectl scale deployment devops-pipeline-staging -n staging --replicas=5
sleep 15
kubectl get pods -n staging
```

ArgoCD brings the count back down to whatever `values-staging.yaml`
declares, with no manual intervention.

**8. Confirm Alertmanager routing**, the same test used since v8.1:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093 &

curl -XPOST http://localhost:9093/api/v2/alerts -H "Content-Type: application/json" -d '[
  {
    "labels": {"alertname": "TestAppAlert", "team": "app", "severity": "warning"},
    "annotations": {"summary": "Test alert", "description": "Confirms alerts-app routing on EKS."},
    "startsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'"
  }
]'
```

Should land in `#alerts-app` within the configured `group_wait` window;
the same request with `team: infra` should land in `#alerts-infra`.

**9. Confirm no false-positive alerts from the migration itself:**

```
Grafana -> Alerting -> Alert rules, filtered to state:firing
```

Only `Watchdog` should be firing - none of the disabled
`KubeSchedulerDown`/`KubeControllerManagerDown`/`KubeEtcdDown`/`KubeProxyDown`
rules should have reappeared.

## Cost and safety

The same rule as every version since v5: the cluster is never left
running by accident. `infra.yml`'s `destroy` option removes every
Ingress first (so the Load Balancer Controller tears down the ALB
before anything underneath it is deleted), then the IRSA, EKS cluster,
and network stacks in reverse order. Worth noting explicitly for this
version: an EKS control plane takes longer to create and delete than
the single EC2 instance every prior version used - a full apply or
destroy cycle typically takes 15-20 minutes, most of it the control
plane and node group themselves, not anything this project's own code
is doing.

## What's next

v10 is the project's final planned version. The roadmap that started
at v1 (a Flask app in a single Docker container) ends here with a
managed, IRSA-secured, self-healing Kubernetes cluster on AWS - each
version along the way its own tested, tagged checkpoint, recoverable
independently of everything that came after it.
