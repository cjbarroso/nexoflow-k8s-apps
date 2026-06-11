# hhccia-v2 (manifests)

Kubernetes manifests for the HHCCIA **v2** architecture (source-agnostic AI core
+ Datatech adapter, event-driven over NATS). Deployed to namespace `hhccia-v2`,
**separate from** the live `hhccia` namespace so it doesn't affect the current
system.

Argo `Application`: `apps/hhccia-v2/hhccia-v2.yaml` (project `hhccia`,
automated sync with prune + selfHeal — v2 is the live stack).

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
2. Build & push the images — CI for each app repo publishes
   `ghcr.io/irupe-consultores/<name>:latest` + `:<git-sha>` on green tests
   (the manifests here pin the `:<git-sha>` tag).
3. Keep the adapter in `SOURCE_MODE=sample` until the v3 query + MSSQL
   connectivity are wired; then flip to `datatech`.

## Deploying a freshly built image

CI in `hhccia-core`, `hhccia-front` and `hhccia-adapter-datatech` runs the test
suite and, on green, pushes images tagged `:latest` + `:<git-sha>` to GHCR.

These manifests pin the **`:<git-sha>` tag** — immutable and traceable to the
exact source commit, so Git is the single record of what runs in the cluster.
To deploy a new build:

1. Get the SHA of the last successful publish run: `task images:latest`
   (or copy the commit SHA from the green Actions run in the app repo).
2. Update the `image:` tag in the matching manifest in this directory.
3. Commit & push to `master` — Argo CD syncs and rolls the Deployment.

Rollback is `git revert` of the bump commit. Do **not** go back to `:latest`:
Argo can't detect image-only changes, deploys would need out-of-band
`rollout restart`, and the running version would not be auditable from Git.
