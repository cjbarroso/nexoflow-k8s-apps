# nexoflow-k8s-apps

GitOps repository for the nexoflow Kubernetes cluster. Argo CD reads this repo
and reconciles all cluster resources automatically.

## Directory structure

| Path | Purpose |
|---|---|
| `apps/` | Argo CD Application definitions (app-of-apps) |
| `src/` | Raw Kubernetes manifests per app |
| `bootstrap/` | Cluster bootstrap (root app, Argo config) |
| `tofu/` | OpenTofu infrastructure |
| `docs/` | Architecture, workflows, troubleshooting |

## Adding a new app

1. Create `apps/<app>/app.yaml` with the Argo CD Application definition
2. Add Helm values at `apps/<app>/values.yaml` (or manifests at `src/<app>/`)
3. Commit and push — Argo CD picks it up automatically

See `docs/06-APP-STRUCTURE.md` for the full checklist.

## Developer workflow

| Task | Command |
|---|---|
| Sync an app | `task argo:sync APP=<name>` |
| Show pending diff | `task argo:diff APP=<name>` |
| Port-forward Argo UI | `task argo:connect` |
| Login to Argo | `task argo:login` |
| Latest HHCCIA image SHAs | `task images:latest` |

## Docs

- `docs/02-ARCHITECTURE.md` — directory structure and conventions
- `docs/06-APP-STRUCTURE.md` — adding a new app
- `docs/03-WORKFLOWS.md` — operational workflows
- `docs/04-TROUBLESHOOTING.md` — common issues
- `docs/05-VAULTWARDEN-UPDATE-NOTES.md` — Vaultwarden image updates
- `docs/08-MSSQL-TUNNEL-RUNBOOK.md` — connecting to on-prem MSSQL via the tunnel
