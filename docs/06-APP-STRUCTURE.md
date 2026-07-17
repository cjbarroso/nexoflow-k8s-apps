# Adding a New App

Use this checklist whenever you introduce another workload under the `apps/` directory. It captures the conventions and gotchas learned from every app deployed so far.

## 1. Choose a deployment pattern

There are three patterns, chosen based on whether an upstream Helm chart exists and whether you need raw K8s manifests alongside it:

| Pattern | When to use | Example apps |
|---------|-------------|--------------|
| **A — Helm chart + values file** | An upstream Helm chart exists and covers the app fully. | `velero`, `longhorn`, `vaultwarden` |
| **B — Raw manifests from `src/`** | No Helm chart, or you need full control over every resource. | `hermes2`, `pami`, `authentik` |
| **C — Helm chart + values + raw manifests** | The chart covers most of the app but you need extras (CNPG database, SealedSecrets, NetworkPolicies). | `planka`, `caldiy`, `obs` stack (`loki`, `grafana`) |

## 2. Create the app directory and files

```
apps/<app-name>/          # Argo CD Application + Helm values
src/<app-name>/           # Raw manifests (CNPG, SealedSecrets, policies)
```

> Use `kebab-case` to match existing names (e.g., `vaultwarden`, `caldiy`, `hhccia-v2`).

### Minimal files per pattern

**Pattern A** (Helm only):
```
apps/<app-name>/
├── app.yaml                  # Argo CD Application
└── <app-name>-values.yaml    # Helm values (loaded via $values/...)
```

**Pattern B** (raw manifests only):
```
apps/<app-name>/
└── app.yaml                  # Argo CD Application (source.path: src/<app-name>)
src/<app-name>/
├── deployment.yaml
├── service.yaml
├── ingress.yaml
└── ...
```

**Pattern C** (Helm + raw):
```
apps/<app-name>/
├── app.yaml                           # Argo CD Application (3-source)
└── <app-name>-values.yaml             # Helm values
src/<app-name>/
├── postgres-cnpg.yaml                 # CNPG Cluster + ObjectStore + ScheduledBackup
├── <name>-sealedsecret.yaml           # SealedSecrets the chart consumes by name
├── <name>-db-bootstrap-sealedsecret.yaml
├── <name>-db-backup-creds-sealedsecret.yaml
├── networkpolicies.yaml               # (optional)
└── secrets.example.yaml               # (optional) template excluded from Argo sync
```

## 3. Define the Helm values file

Key sections that appear in most values files:

- **`image`**: `repository`, `tag`, `pullPolicy`. Pin to immutable tags (git SHA or semver), never `latest`.
- **`imagePullSecrets`**: If pulling from GHCR, add `[{ name: github-auth }]`. The secret must exist in the target namespace (copy from an existing namespace if absent).
- **`secretRef` / `existing*Secret`**: charts reference K8s Secrets by name. Create matching SealedSecrets in `src/<app-name>/`.
- **`service`**: `type: ClusterIP`, `port` (usually 80 for the ingress).
- **`ingress`**: `className: cloudflare-tunnel`, host at `<app-name>.irupeconsultores.com`.
- **`resources`**: start with `requests: { cpu: 100m, memory: 256Mi }`, tune from there.
- **`postgresql.enabled: false`** — disable the chart's bundled PostgreSQL if using CNPG.

For charts based on `bjw-s/app-template`, also set `controllers`, `persistence`, `configMaps`, etc.

Keep secrets out of Git — reference existing Secrets via `valueFrom` or `existing*Secret`. The Secrets themselves are deployed as SealedSecrets in `src/`.

## 4. Create the Argo CD Application

### Pattern A (Helm chart + values)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  project: <project-name>
  sources:
    - chart: <helm-chart-name>
      repoURL: <helm-repo-url>
      targetRevision: <chart-version>
      helm:
        valueFiles:
          - $values/apps/<app-name>/<app-name>-values.yaml
    - repoURL: https://github.com/cjbarroso/nexoflow-k8s-apps.git
      targetRevision: master
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: <app-name>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true   # omit for CNPG-backed apps (see note below)
```

### Pattern C (Helm chart + values + raw manifests)

Add a **third source** pointing at `src/<app-name>/`:

```yaml
spec:
  project: <project-name>
  sources:
    - chart: <helm-chart-name>          # Source 1: upstream Helm chart
      repoURL: <helm-repo-url>
      targetRevision: <chart-version>
      helm:
        valueFiles:
          - $values/apps/<app-name>/<app-name>-values.yaml
    - repoURL: https://github.com/cjbarroso/nexoflow-k8s-apps.git
      targetRevision: master
      ref: values                        # Source 2: this repo (ref for values)
    - repoURL: https://github.com/cjbarroso/nexoflow-k8s-apps.git
      targetRevision: master
      path: src/<app-name>               # Source 3: raw manifests
      directory:
        exclude: '*.example.yaml'        # keep templates out of sync
```

### Notes on ServerSideApply

- **Do NOT use** `ServerSideApply=true` when the app includes CNPG Cluster resources. CNPG's webhook defaults fields that SSA attributes to Argo's field manager, causing permanent OutOfSync. Use client-side apply (omit the flag) — it diffs via `last-applied-` annotation and ignores live-only defaults.
- Use SSA for apps with large CRDs (e.g., velero, cert-manager) where client-side apply can't handle the payload size.

## 5. Register the app project

Every app belongs to an Argo CD AppProject. Projects are defined in `apps/projects.yaml`.

If an existing project covers the app (e.g., `hhccia-v2` under `hhccia`), just add the namespace to that project's `destinations`. Otherwise, create a new project:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: <app-name>
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: <description>
  sourceRepos:
    - 'https://github.com/cjbarroso/nexoflow-k8s-apps.git'
    - '<helm-repo-url>'          # if using an upstream chart
  destinations:
    - { server: 'https://kubernetes.default.svc', namespace: <app-name> }
  # Namespace only — everything else (Deployment, CNPG, SealedSecrets) is namespaced.
  clusterResourceWhitelist:
    - { group: '', kind: Namespace }
```

Projects with cluster-scoped resources (CRDs, ClusterRoles, webhooks) need a broader `clusterResourceWhitelist` — see the `support` or `operators` projects in `apps/projects.yaml`.

## 6. Database with CloudNativePG (CNPG)

If the app needs PostgreSQL, use CNPG instead of the chart's bundled PostgreSQL or a standalone Deployment. This gives you WAL archiving to R2, PITR, and daily backups for free.

Create `src/<app-name>/postgres-cnpg.yaml` with three resources:

### 6a. CNPG Cluster

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <app-name>-db
  namespace: <app-name>
spec:
  instances: 2
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  primaryUpdateStrategy: unsupervised
  affinity:
    enablePodAntiAffinity: true
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: <app-name>-db-store
  bootstrap:
    initdb:
      database: <app-name>
      owner: <app-name>
      encoding: UTF8
      localeCollate: C
      localeCType: C
  storage:
    size: 5Gi
    storageClass: local-path
```

**Known-password bootstrap**: If the Helm chart reads credentials from one secret (e.g., `secretRef: caldiy`) and can't consume a separate CNPG-generated secret (no `existingDburlSecret` option), use `bootstrap.initdb.secret` to provide known credentials:

```yaml
  bootstrap:
    initdb:
      database: <app-name>
      owner: <app-name>
      secret:
        name: <app-name>-db-bootstrap   # SealedSecret with username + password
```

The same password goes into the app's main Secret as `DATABASE_URL`. This avoids the chicken-and-egg problem where CNPG auto-generates a random password the Helm chart can't read.

### 6b. ObjectStore (R2)

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: <app-name>-db-store
  namespace: <app-name>
spec:
  retentionPolicy: "30d"
  configuration:
    destinationPath: s3://velero-backups/cnpg/<app-name>-db
    endpointURL: https://77df3d66af9eb572fe180d800d44127b.r2.cloudflarestorage.com
    s3Credentials:
      accessKeyId:
        name: <app-name>-db-backup-creds
        key: accessKeyId
      secretAccessKey:
        name: <app-name>-db-backup-creds
        key: secretAccessKey
    wal:
      compression: gzip
    data:
      compression: gzip
```

### 6c. ScheduledBackup

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: <app-name>-db-daily
  namespace: <app-name>
spec:
  schedule: "0 0 4 * * *"       # stagger after other apps
  backupOwnerReference: self
  immediate: true               # take one base backup immediately
  cluster:
    name: <app-name>-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

**Stagger backup times** so backups don't pile up at the same hour:
- velero: `0 0 2 * * *`
- hhccia: `0 0 3 * * *`
- authentik: `0 30 3 * * *`
- planka: `0 45 3 * * *`
- caldiy: `0 0 4 * * *`

The R2 credentials (`accessKeyId` / `secretAccessKey`) are shared across all apps. Get them from an existing backup creds Secret in the cluster.

## 7. Secrets with SealedSecrets

Every secret goes through Bitnami SealedSecrets. The controller decrypts `SealedSecret` resources into regular `Secret` resources in the same namespace.

### Workflow

1. **Create a plain Secret YAML** with `stringData` and `REPLACE_ME` placeholders:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: <name>
     namespace: <app-name>
   type: Opaque
   stringData:
     KEY: "REPLACE_ME"
   ```
   Save as `src/<app-name>/<name>-sealedsecret.yaml.example`. This template is excluded from Argo sync via `exclude: '*.example.yaml'` in the Application.

2. **Generate real values** and create a temp Secret file:
   ```powershell
   kubeseal --controller-name=sealed-secrets-controller `
       --controller-namespace=kube-system --format=yaml `
       < <temp-secret.yaml> src/<app-name>/<name>-sealedsecret.yaml
   ```

3. **Commit** the `.yaml` result (drop `.example`). The SealedSecrets controller decrypts it on sync.

### Secrets you typically need

| Secret | Content | Source |
|--------|---------|--------|
| `<app-name>` | `DATABASE_URL`, `NEXTAUTH_SECRET`, `CALENDSO_ENCRYPTION_KEY`, `NEXT_PUBLIC_WEBAPP_URL` | Generated |
| `<app-name>-db-bootstrap` | `username`, `password` (CNPG bootstrap credentials) | Generated (password must match `DATABASE_URL`) |
| `<app-name>-db-backup-creds` | `accessKeyId`, `secretAccessKey` (R2) | Copy from existing app's backup secret in the cluster |

### Kubernetes secrets you also need

| Secret | How to get |
|--------|-----------|
| `github-auth` | Copy from an existing namespace (`kubectl get secret -n <ns> github-auth -o yaml`, strip namespace/metadata, apply to new namespace). This is a `docker-registry` type secret used by `imagePullSecrets` to pull from GHCR. |

## 8. Register the app — no extra wiring needed

`bootstrap/root-app.yaml` already points Argo CD at the `apps/` directory with `recurse: true`. Committing the new folder is enough — Argo auto-discovers the new Application. Run `argocd app sync <app-name>` to speed up the first sync.

## 9. Forking a project & publishing a custom image

If the app doesn't have a published Docker image (e.g., `cal.diy` has no tags on Docker Hub):

1. **Fork** the repo into the `Irupe-Consultores` org on GitHub.
2. **Add a CI workflow** (`.github/workflows/docker-publish.yml`) that:
   - Triggers on `push` to `main` and `workflow_dispatch`.
   - Builds the Docker image.
   - Tags it as `sha-<commit-sha>` and `latest`.
   - Pushes to `ghcr.io/irupe-consultores/<app-name>`.
   - Uses `GITHUB_TOKEN` for GHCR auth.
3. **Pin the image tag** in the Helm values file to `sha-<full-commit-sha>`.
4. **Renovate** ignores `ghcr.io/irupe-consultores/**` (already in `renovate.json`), so image bumps are manual — run the CI, then update the tag and commit.

If the CI needs a database at build time (e.g., for Prisma), add a PostgreSQL service container to the workflow.

### CI workflow template

```yaml
name: Build and push Docker image
on:
  push: { branches: [main] }
  workflow_dispatch:
permissions:
  contents: read
  packages: write
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: irupe-consultores/<app-name>
jobs:
  build:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: <db-user>
          POSTGRES_PASSWORD: <db-pass>
          POSTGRES_DB: <db-name>
        options: >-
          --health-cmd pg_isready
          --health-interval 10s --health-timeout 5s --health-retries 5
        ports: [5432:5432]
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=sha-${{ github.sha }}
            type=raw,value=latest
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          build-args: |
            DATABASE_URL=postgresql://<db-user>:<db-pass>@localhost:5432/<db-name>
```

## 10. Gotchas & lessons learned

| Issue | Fix |
|-------|-----|
| **GHCR package is private** → `401 Unauthorized` or `not found` | Keep the package **private**, and ensure the `github-auth` imagePullSecret exists in the app's namespace. On first deploy, copy it from an existing namespace if the new namespace doesn't have it. |
| **PowerShell `>` creates UTF-16 files** → YAML validation fails | Use `[System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)` instead of `>` redirect. Or convert to UTF-8 with `Set-Content -Encoding UTF8`. |
| **SealedSecrets written with wrong encoding** → `check-yaml` hook fails | The `end-of-file-fixer` pre-commit hook usually fixes this automatically on `git add`. Always let hooks run before pushing. |
| **CNPG + ServerSideApply = permanent OutOfSync** | Omit `ServerSideApply=true` for apps that include CNPG Cluster resources. |
| **`.github/workflows/` can't be modified via REST API** | The regular Contents API returns 404 for files under `.github/workflows/`. Use git push (SSH or PAT with `workflow` scope) instead. |
| **PATCH on git refs requires Accept header** | Always add `-H "Accept: application/vnd.github+json"` when modifying refs via `gh api`. |
| **Image tag mismatches** | Double-check the SHA in the values file matches the exact tag pushed to GHCR. The CI log shows the tag, or query: `gh api .../packages/container/<name>/versions` |
| **Argo doesn't detect new apps immediately** | Root app syncs every 3 min by default. Run `argocd app sync <app-name>` to trigger immediately. |

---
Following this pattern keeps every app consistent, makes diffs predictable, and lets Argo CD manage them uniformly.
