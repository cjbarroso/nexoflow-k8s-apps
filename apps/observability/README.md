# observability — lightweight logs + metrics

A simple, light meta-monitoring stack for the cluster: **logs** (Loki + Alloy)
and **metrics** (Prometheus + node-exporter), viewed through one Grafana. Logs
are **opt-in per component** (nothing collected unless you ask); node/cluster
metrics are scraped cluster-wide.

## Stack

| File | What it deploys | Notes |
|------|-----------------|-------|
| `loki.yaml` + `loki-values.yaml` | **Grafana Loki** | Monolithic mode, filesystem storage, 1 replica, **30-day** retention. The log store. PVC on **Longhorn** (replicated) so it reschedules on a node loss. |
| `alloy.yaml` + `alloy-values.yaml` | **Grafana Alloy** | DaemonSet collector (Promtail's successor — Promtail is EOL). Tails `/var/log/pods`, ships **only opt-in pods**. One pod per node — scales with the cluster. |
| `prometheus.yaml` + `prometheus-values.yaml` | **Prometheus** | The metric store (node analogue of Loki). Single server, **16Gi PVC on Longhorn** (replicated → reschedules on node loss), **15-day** retention, sized for a 3-node cluster. Bundled **node-exporter** DaemonSet (node CPU/mem/disk, one pod/node) + kubelet/cAdvisor scrape (per-pod) + **kube-state-metrics** (cluster objects). Also scrapes the **k3s embedded-etcd** quorum (`:2381`). Pushgateway **off**. A minimal **Alertmanager** (no PVC) runs only to drive the healthchecks.io heartbeat (below). Internal-only (no ingress). |
| `grafana.yaml` + `grafana-values.yaml` | **Grafana** | UI at `https://logs.cjbarroso.com`, Authentik SSO. **Loki** (default) + **Prometheus** + **Tempo** datasources pre-wired (trace↔log↔metric correlations); auto-imports the **Node Exporter Full** dashboard. PVC on **Longhorn** (node-mobile). |
| `tempo.yaml` + `tempo-values.yaml` | **Grafana Tempo** | Single-binary mode, filesystem storage, 1 replica, **14-day** retention. The **trace store** (trace analogue of Loki). PVC on **Longhorn**. OTLP-only ingest, **from Alloy only**, no ingress (queried via Grafana). ⚠️ the single-binary chart is upstream-**deprecated** — kept deliberately (lightest fit); see `tempo.yaml` header. |
| `alloy-gateway.yaml` + `alloy-gateway-values.yaml` | **Grafana Alloy** (trace gateway) | **Deployment, 1 replica** (distinct from the log DaemonSet). Receives OTLP from the apps, **tail-samples** (errors + slow at 100%, ~15% baseline), **scrubs PHI** attributes, forwards to Tempo. One replica so tail-sampling sees whole traces. |
| `observability-secrets.yaml` | Argo **directory app** → `src/observability/` | Applies the sealed `grafana-secrets`. |

All Helm apps live in project `support`, namespace `observability`,
auto-synced. Chart versions are **pinned and validated with `helm template`**:
loki `17.3.1`, alloy `1.9.0`, grafana `12.4.4`, prometheus `29.10.1`,
tempo `1.24.4`. Prometheus needs **no secret** — internal, no auth.

> **Cluster-object metrics** (deployment desired vs available, pod restarts, job
> status) come from **kube-state-metrics**, enabled in `prometheus-values.yaml`
> (one pod). node-exporter + cAdvisor cover host + per-pod CPU/memory.

> **3-node cluster (since 2026-07-08):** the scrape layer needed no changes —
> node-exporter + Alloy are DaemonSets and discovery is endpoint/annotation based,
> so all 3 nodes are picked up automatically. What changed: node-availability +
> etcd-quorum alerts were added (see the alerts table), Prometheus was resized for
> ~3× the series, and the Prometheus/Grafana/Loki PVCs moved to Longhorn so the
> stack survives (reschedules on) a node loss instead of dying with `homestation`.
> The migration steps (immutable-storageClass surgery) are in the migration SIF.

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

`https://logs.cjbarroso.com` → **Dashboards → Node Exporter Full** for the full
per-node breakdown, or **Node Alerts — CPU / Memory / Disk**
(`/d/node-alerts`) for just the three metrics we alert on, each with its
threshold drawn as a line. Or **Explore** → datasource **Prometheus** for
ad-hoc PromQL:

```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)   # CPU %/node
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)            # mem %/node
100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}                    # disk %/mount
       / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"})
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="hhccia-v2"}[5m]))  # per-pod CPU (cAdvisor)
```

Prometheus has **no ingress** — query it through Grafana. For raw access:
`kubectl -n observability port-forward svc/prometheus-server 9090:80`.

## Tracing (Tempo)

Distributed traces flow **apps → Alloy gateway → Tempo**, and are viewed in the
same Grafana. The apps (`hhccia-core`, `hhccia-adapter-datatech`) are
instrumented with OpenTelemetry and export OTLP.

**To send traces from a workload:** point it at the gateway and name the service.
The apps read these as env vars (pydantic-settings); set them on the Deployment:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://alloy-gateway.observability.svc.cluster.local:4317"   # OTLP/gRPC
  - name: OTEL_SERVICE_NAME
    value: "hhccia-core"          # becomes the span service.name (must match the pod `app` label for trace→logs)
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=prod"   # or =staging, to split envs in one Tempo
```

The gateway **tail-samples** (keeps all error + slow traces, ~15% of the rest)
and **scrubs PHI** attributes as a safety net — but the primary rule is
**app-side: never put HCL, PAC, patient identity, or clinical text in span names
or attributes** (mirrors the HCL/PAC log masking in `alloy-values.yaml`).

**Viewing traces:** `https://logs.cjbarroso.com` → **Explore** → datasource
**Tempo** → search by service/duration/tags, or paste a trace ID. From a span:
**Logs for this span** jumps to Loki; **Related metrics** jumps to Prometheus.
Prometheus panels with a `trace_id` exemplar link back into Tempo.

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
| `NodeHighMemory` | node memory in use > 85% (100 − available) for > 5 min |
| `NodeDiskSpaceLow` | a real, writable filesystem has < 15% free for > 10 min |
| `NodeNotReady` | a node is `NotReady` (API view) for > 5 min |
| `ClusterNodeCountLow` | fewer than 3 nodes registered with the API for > 10 min |
| `ScrapeTargetDown` | an infra scrape target (node-exporter / kube-state) unreachable > 10 min |
| `EtcdNoLeader` | an etcd member reports no leader for > 1 min |
| `EtcdMembersDown` | fewer than 3 etcd members reporting for > 5 min (quorum risk) |
| `EtcdLeaderFlapping` | > 3 etcd leader changes in 15 min (unstable control plane) |

(Plus non-node rules: `CNPGWALArchivingFailing`, `CNPGReplicationLagHigh`,
`HHCCIACoreConsumersMissing`, `HHCCIACoreDeadLetters`, `KubePodCrashLooping`,
`KubeJobFailed`, `PVCSpaceLow`, `VeleroBackupFailed`, and the Loki-ruler log
alerts.) The **etcd** rules need `etcd-expose-metrics: true` on each k3s server —
see the migration SIF.

To add an alert, append a rule with a `severity: warning` (or `critical`) label —
routing is automatic. The Telegram **bot token** is the sealed Secret
`alertmanager-notify` (key `telegram-bot-token`, read via `bot_token_file`); the
non-secret `chat_id` is in `prometheus-values.yaml`. Bring-up: `../../src/observability/README.md` §2c.

Each Telegram message includes the alert description and a **deep-link to the
`node-alerts` dashboard** (the relevant panel, last 3h). The link comes from each
rule's `dashboard` annotation, rendered by the custom `message` template on the
`notify` receiver — add a `dashboard` annotation to new rules to get the same.

## First-time bring-up

See `../../src/observability/README.md` for the out-of-band prerequisites
(Authentik OAuth app, sealing the Grafana secret, pinning chart versions).
Until the secret is sealed, the Grafana pod stays `Pending` — that's expected.
