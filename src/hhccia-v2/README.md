# hhccia-v2 (manifests)

Kubernetes manifests for the HHCCIA **v2** architecture (source-agnostic AI core
+ Datatech adapter, event-driven over NATS). Deployed to namespace `hhccia-v2`,
**separate from** the live `hhccia` namespace so it doesn't affect the current
system.

Argo `Application`: `apps/hhccia-v2/hhccia-v2.yaml` (project `hhccia`, **manual
sync** while in testing).

## Components

| File | Workload |
|------|----------|
| `nats.yaml` | NATS + JetStream event bus (test-grade, emptyDir store) |
| `postgres.yaml` | Standalone Postgres for the core store (prod option: shared CNPG) |
| `hhccia-core.yaml` | AI Core Service (FastAPI) + Service |
| `hhccia-core-ingress.yaml` | Cloudflare-tunnel ingress → `api-hhccia-v2.cjbarroso.com` |
| `hhccia-adapter-datatech.yaml` | Datatech adapter (starts in `sample` mode) |
| `secrets.example.yaml` | PLACEHOLDER secret template (excluded from Argo; replace via sealed-secrets) |

## Before syncing

1. Provide the real `hhccia-core-secrets` Secret (sealed-secrets/vault), keeping
   `PG_PASSWORD` consistent with `DATABASE_URL`.
2. Build & push the two images — CI for `hhccia-core` and
   `hhccia-adapter-datatech` must publish to
   `ghcr.io/irupe-consultores/<name>:latest` (mirror the existing front workflow).
3. Keep the adapter in `SOURCE_MODE=sample` until the v3 query + MSSQL
   connectivity are wired; then flip to `datatech`.

Nothing here auto-deploys: the root app tracks `master`, and this Application
uses manual sync.
