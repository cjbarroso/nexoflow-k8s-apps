# observability — lightweight logs + metrics

A simple, light meta-monitoring stack for the cluster: **logs** (Loki + Alloy)
and **metrics** (Prometheus + node-exporter), viewed through one Grafana. Logs
are **opt-in per component** (nothing collected unless you ask); node/cluster
metrics are scraped cluster-wide.

## Stack

| File | What it deploys | Notes |
|------|-----------------|-------|
| `loki.yaml` + `loki-values.yaml` | **Grafana Loki** | Monolithic mode, filesystem storage, 1 replica, **30-day** retention. The log store. |
| `alloy.yaml` + `alloy-values.yaml` | **Grafana Alloy** | DaemonSet collector (Promtail's successor — Promtail is EOL). Tails `/var/log/pods`, ships **only opt-in pods**. |
| `prometheus.yaml` + `prometheus-values.yaml` | **Prometheus** | The metric store (node analogue of Loki). Single server, 8Gi PVC, **15-day** retention. Bundled **node-exporter** DaemonSet (node CPU/mem/disk) + kubelet/cAdvisor scrape (per-pod). Pushgateway/kube-state-metrics **off** to stay light. A minimal **Alertmanager** (no PVC) runs only to drive the healthchecks.io heartbeat (below). Internal-only (no ingress). |
| `grafana.yaml` + `grafana-values.yaml` | **Grafana** | UI at `https://logs.cjbarroso.com`, Authentik SSO. **Loki** (default) + **Prometheus** datasources pre-wired; auto-imports the **Node Exporter Full** dashboard. |
| `observability-secrets.yaml` | Argo **directory app** → `src/observability/` | Applies the sealed `grafana-secrets`. |

All Helm apps live in project `support`, namespace `observability`,
auto-synced. Chart versions are **pinned and validated with `helm template`**:
loki `7.0.0`, alloy `1.8.2`, grafana `10.5.15` (2026-05-29); prometheus `29.9.0`
(2026-05-30). Prometheus needs **no secret** — internal, no auth.

> **Want per-workload / cluster-object metrics** (deployment desired vs available,
> etc.)? Set `kube-state-metrics.enabled: true` in `prometheus-values.yaml` — it's
> one pod. node-exporter + cAdvisor already cover host + per-pod CPU/memory.

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

## Viewing metrics

`https://logs.cjbarroso.com` → **Dashboards → Node Exporter Full** for per-node
CPU / memory / disk / filesystem / network. Or **Explore** → datasource
**Prometheus** for ad-hoc PromQL:

```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)   # CPU %/node
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)            # mem %/node
100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}                    # disk %/mount
       / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"})
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="hhccia-v2"}[5m]))  # per-pod CPU (cAdvisor)
```

Prometheus has **no ingress** — query it through Grafana. For raw access:
`kubectl -n observability port-forward svc/prometheus-server 9090:80`.

## Uptime alerting (healthchecks.io dead-man's switch)

An always-firing `Watchdog` rule (`vector(1)`) feeds Alertmanager, which pings a
healthchecks.io check every 5 min. If Prometheus or Alertmanager stops, the pings
stop and healthchecks.io alerts you. The ping URL is a credential, kept in the
sealed Secret `prometheus-hc-ping` (key `url`) and read by Alertmanager via
`url_file` — never in Git. Set it up (and the healthchecks.io check) per
`../../src/observability/README.md` §2b. The `prometheus-alertmanager` pod stays
pending until that Secret is sealed — expected.

## Alerts → Telegram

Alerting rules live in `prometheus-values.yaml` under `serverFiles.alerting_rules.yml`.
Any rule labelled `severity: warning|critical` routes through Alertmanager to a
**Telegram** chat (receiver `notify`). Currently defined:

| Alert | Fires when |
|-------|-----------|
| `NodeHighCpu` | node CPU > 80% (100 − idle) for > 5 min |

To add an alert, append a rule with a `severity: warning` (or `critical`) label —
routing is automatic. The Telegram **bot token** is the sealed Secret
`alertmanager-notify` (key `telegram-bot-token`, read via `bot_token_file`); the
non-secret `chat_id` is in `prometheus-values.yaml`. Bring-up: `../../src/observability/README.md` §2c.

## First-time bring-up

See `../../src/observability/README.md` for the out-of-band prerequisites
(Authentik OAuth app, sealing the Grafana secret, pinning chart versions).
Until the secret is sealed, the Grafana pod stays `Pending` — that's expected.
