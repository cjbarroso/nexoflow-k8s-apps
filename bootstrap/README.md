# Bootstrap

Initial cluster wiring for the Argo CD app-of-apps. The GitOps source of truth is
**GitHub** (`github.com/cjbarroso/nexoflow-k8s-apps`).

> Note: this cluster was originally bootstrapped from a self-hosted **soft-serve**
> git server; that was removed on 2026-05-31 (Argo now pulls from GitHub).

## Contents
- `repo-secret.yaml` — Argo CD credential to clone the private GitHub repo.
- `root-app.yaml` — the app-of-apps; points Argo at `apps/` with `recurse: true`
  (every subdir under `apps/` is scanned and deployed).
- `argocd-config/` — `argocd-cm` (resource exclusions, etc.) + the Argo ingress.
- `barman-cloud/` — kustomization for the CNPG barman-cloud plugin.

## Bootstrap order
1. Install Argo CD into the cluster.
2. `kubectl apply -f bootstrap/repo-secret.yaml` (so Argo can clone the repo).
3. `kubectl apply -f bootstrap/argocd-config/` and `bootstrap/root-app.yaml`.
4. Argo CD reconciles `apps/` and deploys everything (operators, then apps).

For full DR (restore the sealed-secrets master key BEFORE apps sync, then restore
state from R2), see the HHCCIA hub:
`Reference/Disaster Preparedness - full backup coverage plan.md`.
