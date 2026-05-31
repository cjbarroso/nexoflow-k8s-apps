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
| `postgres.yaml` | CNPG operator-managed Postgres `Cluster` (`hhccia-core-db`, 2 instances) + `hhccia-core-pg` ExternalName alias |
| `hhccia-core-db-app-sealedsecret.yaml` | Sealed app credentials (`hhccia`) for the CNPG cluster |
| `hhccia-core-db-backup.yaml` | barman-cloud `ObjectStore` (R2) + daily `ScheduledBackup` — WAL archiving + base backups = PITR (30d retention). Restore runbook is in-file. |
| `hhccia-core-db-backup-creds-sealedsecret.yaml` | Sealed R2 credentials for the barman ObjectStore |
| `hhccia-core.yaml` | AI Core Service (FastAPI) + Service |
| `hhccia-core-ingress.yaml` | Cloudflare-tunnel ingress → `api-medaudit.irupeconsultores.com` |
| `hhccia-adapter-datatech.yaml` | Datatech adapter (starts in `sample` mode) |
| `hhccia-front.yaml` | Angular UI (same image as live v1) flipped to v2 via `CORE_API_URL` env |
| `hhccia-front-ingress.yaml` | Cloudflare-tunnel ingress → `medaudit.irupeconsultores.com` |
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

## Pulling a freshly built image

CI in `hhccia-core` and `hhccia-adapter-datatech` (`.github/workflows/publish.yml`)
runs the test suite and, on green, pushes new images to:

- `ghcr.io/irupe-consultores/hhccia-core:latest` + `:<sha>`
- `ghcr.io/irupe-consultores/hhccia-adapter-datatech:latest` + `:<sha>`

These manifests pin `:latest` with `imagePullPolicy: Always`, **so Argo CD will
not roll the workload by itself** — the manifest digest in Git didn't change.
After CI publishes, force the rollout:

```bash
kubectl -n hhccia-v2 rollout restart deploy/hhccia-core
kubectl -n hhccia-v2 rollout restart deploy/hhccia-adapter-datatech
```

(Same pattern as the live `hhccia` app — see the root project notes.)
