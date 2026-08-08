# v9: Load Balancer + AWS CloudFormation

**Concept demonstrated:** Networking, alternative Infrastructure as Code

## Why CloudFormation?

Every version since v5 used Terraform, a multi-cloud IaC tool that talks to AWS
through a provider plugin. CloudFormation is AWS's own, native IaC service -
YAML/JSON templates interpreted directly by AWS, with no third-party provider
in between. Demonstrating both shows the same thing Jenkins demonstrated
alongside GitHub Actions back in v7: fluency with more than one tool in a
category, not just familiarity with whichever one came first. v9 replaces
Terraform entirely rather than running it alongside CloudFormation - the full
Terraform setup stays completely intact and recoverable from the `v8.1.0` tag.

## Why a Load Balancer?

Through v8.1, all three environments lived on one server, each reachable on
its own port (5000/5001/5002). That works, but it isn't how a real user
reaches an app in production - a single address routes to the right place
behind the scenes, not three memorized port numbers. An Application Load
Balancer (ALB) sits in front of all three environments now, routing by URL
path (`/dev`, `/staging`, `/production`) instead of by port.

## Key concepts

- **Cross-stack references**: CloudFormation has no module system the way
  Terraform does. Instead, this version splits into three separate stacks
  (network, compute, load balancer), each exporting values the next one
  imports with `Fn::ImportValue`. This is also closer to how larger,
  real-world CloudFormation setups are usually organized - a network layer
  that rarely changes, underneath layers that change far more often.
- **Path-based routing**: the ALB's Listener has one rule per environment,
  matching `/dev*`, `/staging*`, or `/production*` and forwarding to that
  environment's own Target Group. Host-based routing (separate subdomains)
  was considered and rejected - it would need a real domain, and the whole
  point of a portfolio project is that anyone forking it can test it
  immediately, with no purchase or DNS setup required.
- **NodePort vs. LoadBalancer**: through v8.1, `service.type: LoadBalancer`
  let k3s's built-in Klipper load balancer expose each environment directly.
  The ALB's Target Groups register an EC2 instance and a fixed port
  directly, which needs `service.type: NodePort` with an explicit,
  pinned `nodePort` instead - Kubernetes has to be told exactly which port
  to reserve, rather than assigning one at random.
- **`APP_URL_PREFIX`**: the Flask app now runs under a Blueprint registered
  with a path prefix, so it can tell whether it's answering as `/dev`,
  `/staging`, or `/production`. `/health` and `/metrics` are deliberately
  kept **outside** that Blueprint, unprefixed - Kubernetes' own
  liveness/readiness probes and Prometheus' ServiceMonitor both hit those
  paths directly against the Pod, never through the ALB's routing, so
  prefixing them would have broken both for no benefit.

## What's included

- **`cloudformation/network-stack.yaml`**: VPC, two public subnets (an ALB
  requires at least two Availability Zones - the EC2 instance only ever
  lives in the first one, the second exists purely to satisfy that
  requirement), Internet Gateway, route table.
- **`cloudformation/compute-stack.yaml`**: the EC2 instance, its Elastic
  IP, the security group, and the IAM Instance Profile carried over from
  v8.1 for Loki's S3 access. The AMI is resolved automatically at deploy
  time from Canonical's own public SSM parameter, the same "always the
  latest" behavior Terraform's `aws_ami` data source gave before.
- **`cloudformation/loadbalancer-stack.yaml`**: the ALB, its security
  group (the only thing in the whole project intentionally open to the
  public internet), three Target Groups, and the path-based Listener
  Rules.
- **SSM Parameter Store**: the server's public IP and the ALB's DNS name
  are written here by `infra.yml` after every apply, replacing the
  GitHub repo Variables used for this in earlier versions - now that
  everything already lives inside AWS, there's less reason to round-trip
  through the GitHub API for it.
- **A new, separate IAM role** (`github-actions-cloudformation-role`) for
  OIDC, scoped only to what CloudFormation, EC2, ELB, the Loki IAM
  resources, and the SSM parameters actually need. The original
  `github-actions-terraform-role` is untouched, so any earlier tag can
  still be applied on its own.
- **Traefik disabled** at k3s install time (`--disable traefik`) - the ALB
  is the real front door now, and Traefik's own automatic Service was
  never part of that path to begin with.

## What changed from v8.1

- `terraform/` removed entirely. Fully recoverable from the `v8.1.0` tag.
- `cloudformation/` (new): the three stacks described above.
- `app/app.py`: added `APP_URL_PREFIX`, registered `/` and `/api/status`
  under a Flask Blueprint with that prefix; `/health` and `/metrics` stay
  on the app's root, unprefixed.
- `app/templates/dashboard.html`: a new "URL prefix" row.
- `helm/devops-pipeline/values.yaml`: `service.type` changed from
  `LoadBalancer` to `NodePort`; added `appUrlPrefix` (default blank) and
  an explicit `nodePort`.
- `helm/devops-pipeline/values-dev.yaml`, `values-staging.yaml`,
  `values-production.yaml`: each sets its own `appUrlPrefix` (`/dev`,
  `/staging`, `/production`) and, for staging/production, an explicit
  `nodePort` matching that environment's Target Group.
- `helm/devops-pipeline/templates/deployment.yaml`: passes
  `APP_URL_PREFIX` into the container.
- `helm/devops-pipeline/templates/service.yaml`: renders an explicit
  `nodePort` when `service.type` is `NodePort`.
- `helm/devops-pipeline/templates/NOTES.txt`: updated post-install
  guidance for the `NodePort` case.
- `monitoring/values.yaml`: Grafana's Service changed from `LoadBalancer`
  to `NodePort`, pinned to `5010` (see "Problems hit along the way"
  below for why this took two attempts).
- `ansible/install-k3s.yml`: widens k3s's NodePort range to `5000-5010`
  and disables Traefik.
- `ansible/deploy-k3s.sh`: reads the server's IP from SSM Parameter Store
  instead of `terraform output`.
- `.github/workflows/infra.yml`: rewritten around `aws cloudformation
  deploy`/`delete-stack` instead of `terraform apply`/`destroy`; writes
  SSM parameters after apply; new OIDC role.
- `VERSION`: bumped to `9.0.0`.

## Setup (for anyone forking this project)

**1. Create the OIDC role for CloudFormation**, separate from the existing
Terraform role. Trust policy (note the `*` after the org and repo name -
GitHub's `sub` claim now includes a numeric ID after each, which an exact
string match would silently reject):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<org>*/<repo>*:environment:aws-infra"
        }
      }
    }
  ]
}
```

Permission policy needs: `cloudformation:*` scoped to this project's
stacks, `ec2:*` and `elasticloadbalancing:*` (both resist fine-grained
scoping - AWS's own guidance is to leave these broad), IAM actions scoped
to just the Loki Instance Profile/Role, `ssm:PutParameter`/`GetParameter`
scoped to `/devops-pipeline/*`, read access to Canonical's public AMI
parameter (`arn:aws:ssm:<region>::parameter/aws/service/canonical/ubuntu/*`
- note the account ID is blank, since it's an AWS-owned parameter), and
`iam:CreateServiceLinkedRole` scoped to
`AWSServiceRoleForElasticLoadBalancing` with a
`iam:AWSServiceName` condition (AWS creates this automatically the first
time an ALB is ever created in an account, and it needs its own explicit
permission separate from ordinary `iam:CreateRole`).

**2. Create the SSH key pair once, by hand**, outside CloudFormation:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/devops-pipeline-key -C "devops-pipeline"

aws ec2 import-key-pair \
  --key-name devops-pipeline-key \
  --public-key-material fileb://~/.ssh/devops-pipeline-key.pub \
  --region us-east-1
```

**3. GitHub repo setup**: same environments, variables, and secrets as
v8.1 - nothing new was added, and `ADMIN_PAT` is no longer needed at all
(SSM Parameter Store replaced what it used to write).

## Testing

**1. Bring up the infrastructure:**

```
# infra.yml -> apply
```

This deploys all three CloudFormation stacks in order, installs k3s,
writes the server IP and ALB DNS name to SSM Parameter Store, and
installs the rest of the stack (monitoring, Loki, Alloy, ArgoCD) exactly
as it did in v8.1.

**2. Confirm the ALB and its Target Groups are healthy**, independent of
whatever's actually deployed on top - this checks the networking layer
in isolation:

```bash
aws elbv2 describe-target-groups --region us-east-1 \
  --names devops-pipeline-dev-tg devops-pipeline-staging-tg devops-pipeline-production-tg \
  --query "TargetGroups[].TargetGroupArn" --output text
```

```bash
aws elbv2 describe-target-health --region us-east-1 --target-group-arn <ARN>
```

All three should report `healthy` on `/health`.

**3. Confirm the app port is no longer reachable directly** - the core
security change this version makes:

```bash
curl -v --max-time 5 http://<server-ip>:5000/health
```

```
curl: (28) Connection timed out after 5003 milliseconds
```

**4. Confirm path-based routing through the ALB itself:**

```bash
curl -vL http://<alb-dns-name>/dev/
curl -vL http://<alb-dns-name>/staging/
curl -vL http://<alb-dns-name>/production/
```

Each should return `200 OK` with the app's dashboard HTML, and each
page's "URL prefix" row should show `/dev`, `/staging`, or `/production`
correctly.

Note the trailing slash: Flask issues a `308` redirect from `/dev` to
`/dev/` for a Blueprint registered at its root path - expected behavior,
not a bug. A plain `curl <alb-dns>/dev` (no `-L`) shows this redirect
directly.

**5. Confirm Grafana on its new port:**

```
http://<server-ip>:5010
```

Open **Dashboards → devops-pipeline: App Metrics**, confirm the
`$environment` dropdown still switches between all three namespaces, and
that the Live Logs panel still streams.

**6. Confirm no false-positive alerts from the NodePort range change:**

```
Grafana -> Alerting -> Alert rules, filtered to state:firing
```

Only `Watchdog` (Alertmanager's own always-on liveness check) should be
firing. None of `KubeSchedulerDown`, `KubeControllerManagerDown`,
`KubeEtcdDown`, or `KubeProxyDown` should appear at all - confirming
these were still correctly disabled in `monitoring/values.yaml` and that
none of this version's NodePort changes accidentally re-exposed them.

**7. Confirm ArgoCD synced correctly** with the new `NodePort`-based
chart, across all three environments:

```bash
kubectl get applications -n argocd
```

```
NAME                         SYNC STATUS   HEALTH STATUS
devops-pipeline-dev          Synced        Healthy
devops-pipeline-production   Synced        Healthy
devops-pipeline-staging      Synced        Healthy
```

## Cost and safety

Same rule as every version since v5: the server is never left running by
accident. `infra.yml`'s `destroy` option tears down all three stacks in
reverse order (load balancer → compute → network), since CloudFormation
won't allow a stack to be deleted while another stack still has an active
`Fn::ImportValue` reference to one of its Exports.

## What's next

**v10.0** is the project's final planned version: migrating from a
hand-built, single k3s server to Amazon EKS - a managed control-plane
with real high availability, IRSA (replacing the IAM Instance Profile
workaround Loki has used since v8.1), and the AWS Load Balancer
Controller (replacing this version's hand-written CloudFormation ALB).
There is no intermediate multi-node k3s version - a hand-rolled
multi-node setup would only ever be a partial imitation of what EKS
already does correctly, so that whole problem is deferred to v10 rather
than solved twice at two different levels of quality.
