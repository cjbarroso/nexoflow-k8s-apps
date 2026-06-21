# hhccia-staging (manifests)

Kubernetes manifests for the **staging** MedAudit IA environment. A parallel copy
of `src/hhccia-v2/` (production), deployed to namespace `hhccia-staging` in the
**same cluster**, sharing the same Argo CD and the `hhccia` AppProject.

Argo `Application`: `apps/hhccia-staging/app.yaml` (project `hhccia`, automated
sync with prune + selfHeal).

## How staging differs from prod (`hhccia-v2`)

| Dimension | Prod (`hhccia-v2`) | Staging (`hhccia-staging`) |
|---|---|---|
| Front host | `medaudit.irupeconsultores.com` | `staging.medaudit.irupeconsultores.com` |
| API host | `api-medaudit.irupeconsultores.com` | `api-staging.medaudit.irupeconsultores.com` |
| Clinical source | Datatech **SRN** (live PII) | Datatech **HHCC** (test DB, write-capable) |
| Postgres | `hhccia-core-db`, 2 instances, R2 PITR | `hhccia-staging-db`, 1 instance, **no backup** |
| Images | `:<git-sha>` (pinned, `IfNotPresent`) | `:staging` (tracks the `staging` code branch) |
| Code branch | `main` | `staging` |
| Authentik | `hhccia` OIDC app | **same** app (staging URIs added to the blueprint) |

Everything else (NATS, network policies, core/adapter/front workloads) mirrors prod.

## Before the first sync — required out-of-band steps

1. **Seal two secrets for THIS namespace** (SealedSecrets are namespace-scoped —
   prod's sealed values cannot be reused). Mirror the kubeseal invocation used for
   the prod secrets, with `--namespace hhccia-staging`:

   - `hhccia-core-secrets` — shape in `secrets.example.yaml`
     (`DATABASE_URL`, `GEMINI_API_KEY`, `MSSQL_USER`/`MSSQL_PASSWORD` for an
     **HHCC** write-capable login, `PG_USER`/`PG_PASSWORD`).
   - `hhccia-staging-db-app` — CNPG role credentials (`username` + `password`),
     matching `PG_USER`/`PG_PASSWORD` above.

   Write the sealed output to `hhccia-core-sealedsecret.yaml` and
   `hhccia-core-db-app-sealedsecret.yaml` in this directory, then commit. Until
   they exist, the core/adapter pods stay pending on the missing secret.

2. **Authentik**: the staging redirect/logout URIs are added to `hhccia-provider`
   in `src/authentik/blueprints.yaml`; after pushing, restart the worker
   (`kubectl rollout restart deploy/authentik-worker -n authentik`).

3. **Images**: push the `staging` branch in each app repo so CI publishes the
   `:staging` tag (see each repo's `.github/workflows/`).

## Auto-rollout mechanism — CI git-write-back

Staging is SHA-pinned (`:staging-<sha>`, `imagePullPolicy: IfNotPresent`), exactly
like prod — Argo only rolls a workload when the manifest **text** changes. So the
trigger is a write-back step in each app repo's CI:

```
push to `staging` branch
  -> CI builds & pushes ghcr.io/.../<repo>:staging + :staging-<sha>
  -> CI checks out THIS gitops repo and rewrites the image line in
     src/hhccia-staging/<workload>.yaml to :staging-<sha>, commits, pushes master
  -> Argo CD auto-syncs the manifest change and rolls the staging Deployment
```

The write-back job lives in each app repo (`update-gitops-staging`, gated on the
`staging` branch). It needs a repo secret **`GITOPS_PAT`** — a fine-grained PAT
with **Contents: write** on `cjbarroso/nexoflow-k8s-apps`. Set it in all three app
repos (`Irupe-Consultores/hhccia-core`, `hhccia-front`, `hhccia-adapter-datatech`).

Prod (`hhccia-v2`) has no write-back — `main` builds keep their manual SHA bump.

The `:staging` tag committed here is only the **bootstrap placeholder** before the
first write-back; expect a brief ImagePullBackOff on first sync until CI lands the
first `:staging-<sha>`.
