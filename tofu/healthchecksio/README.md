# tofu/healthchecksio — healthchecks.io check as code

OpenTofu module that creates the **healthchecks.io check** used by the cluster's
Prometheus/Alertmanager dead-man's switch (the `Watchdog` heartbeat described in
`apps/observability/README.md` and `src/observability/README.md §2b`).

This replaces the "click *New Check* in the healthchecks.io UI" manual step with
declarative code. It targets the **hosted** healthchecks.io SaaS (`hc-ping.com`),
which is what the cluster already pings.

> **Not part of Argo CD.** Argo's root app only recurses `apps/`, so this `tofu/`
> directory is invisible to it. You run `tofu` here by hand; Argo manages the
> Kubernetes side. The only thing that crosses between them is the **ping URL**,
> which you seal into a Secret (see below).

## What it creates

| Setting | Value | Why |
|---------|-------|-----|
| name | `nexoflow-prometheus-watchdog` | identifies the cluster heartbeat |
| period (`timeout`) | 600s / 10 min | Alertmanager pings every 5 min |
| grace | 300s / 5 min | one delayed ping ≠ alarm; real outage surfaces in ~15 min |
| channels | `*` (all integrations) | so you actually get notified when it goes down |

All overridable via `variables.tf` / a `terraform.tfvars` (see `terraform.tfvars.example`).

## Prerequisites

- [OpenTofu](https://opentofu.org/) `>= 1.6` (`tofu`) — or Terraform `>= 1.0`.
- A healthchecks.io **project API key** (read-write):
  Project → **Settings → API Access → API key**.
- Notification integrations (email, Telegram, …) configured in the healthchecks.io
  project UI — `channels = ["*"]` assigns the check to all of them.

## Usage

```bash
cd tofu/healthchecksio

# API key via env var — never commit it.
export HEALTHCHECKSIO_API_KEY=hcio_xxx        # PowerShell: $env:HEALTHCHECKSIO_API_KEY="hcio_xxx"

tofu init
tofu plan
tofu apply
```

### Wire the ping URL into the cluster

The check's ping URL is a secret and is **not** stored in Git. After `apply`:

```bash
tofu output -raw ping_url        # -> https://hc-ping.com/<uuid>
```

Seal that into the `prometheus-hc-ping` Secret exactly as in
`src/observability/README.md §2b`:

```bash
kubectl create secret generic prometheus-hc-ping -n observability \
  --from-literal=url="$(tofu output -raw ping_url)" \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller \
    --controller-namespace kube-system -o yaml \
> ../../src/observability/prometheus-hc-ping-sealedsecret.yaml
```

Commit the sealed secret, `argocd app sync observability-secrets`, and the
`prometheus-alertmanager` pod stops pending and starts pinging.

## State

State is **local** and gitignored (it contains the secret `ping_url`). For a
single check that's fine; just don't delete the `.tfstate`, or `tofu` will lose
track and try to create a duplicate check on the next apply. The committed
`.terraform.lock.hcl` pins the provider hashes for reproducible `init`.
