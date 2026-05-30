# observability — lightweight log aggregator

A simple, light log-aggregation stack for the cluster. Logs are **opt-in per
component**: nothing is collected unless you ask for it.

## Stack

| File | What it deploys | Notes |
|------|-----------------|-------|
| `loki.yaml` + `loki-values.yaml` | **Grafana Loki** | Monolithic mode, filesystem storage, 1 replica, **30-day** retention. The log store. |
| `alloy.yaml` + `alloy-values.yaml` | **Grafana Alloy** | DaemonSet collector (Promtail's successor — Promtail is EOL). Tails `/var/log/pods`, ships **only opt-in pods**. |
| `grafana.yaml` + `grafana-values.yaml` | **Grafana** | UI at `https://logs.cjbarroso.com`, Authentik SSO, Loki datasource pre-wired. |
| `observability-secrets.yaml` | Argo **directory app** → `src/observability/` | Applies the sealed `grafana-secrets`. |

All three Helm apps live in project `support`, namespace `observability`,
auto-synced. Chart versions are **pinned and validated with `helm template`**
(2026-05-29): loki `7.0.0`, alloy `1.8.2`, grafana `10.5.15`.

## How to aggregate a component's logs (the one knob)

Add this label to the **pod template** (`spec.template.metadata.labels`) of any
Deployment/StatefulSet/DaemonSet you want collected:

```yaml
spec:
  template:
    metadata:
      labels:
        logs.cjbarroso.com/collect: "true"
```

Then roll the workload (`kubectl rollout restart ...`). Alloy picks it up within
seconds. Remove the label (and roll) to stop collecting. No Alloy config change
is ever needed — the opt-in gate lives in `alloy-values.yaml`.

`hhccia-v2` (core, adapter, front) is already labelled in `src/hhccia-v2/`.

## Viewing logs

`https://logs.cjbarroso.com` → log in via Authentik → **Explore** → datasource
**Loki**. Example queries:

```logql
{namespace="hhccia-v2"}                      # everything in v2
{namespace="hhccia-v2", app="hhccia-core"}   # just the core
{namespace="hhccia-v2"} |= "error"           # text filter
```

## First-time bring-up

See `../../src/observability/README.md` for the out-of-band prerequisites
(Authentik OAuth app, sealing the Grafana secret, pinning chart versions).
Until the secret is sealed, the Grafana pod stays `Pending` — that's expected.
