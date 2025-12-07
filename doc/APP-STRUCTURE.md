# Adding a New App

Use this checklist whenever you introduce another workload under the `apps/` directory. It captures the conventions that existing apps follow so you can scaffold new ones quickly.

## 1. Create the app directory
```
apps/<app-name>/
```
Every app gets its own folder that contains, at minimum, two files:
- `<app-name>-values-production.yaml`
- `<app-name>-chart.yaml` (the Argo CD Application definition)

> Use `kebab-case` to match existing names (e.g., `waha`, `vaultwarden`, `chatui`).

## 2. Define the Helm values file
The values file feeds the upstream Helm chart. Structure it the same way we did for WAHA (which uses the bjw-s `app-template`). Key sections:

- `controllers`: declare the controller type (`deployment`, `statefulset`, etc.), container image (`repository`, `tag`, `pullPolicy`), env vars, ports, probes, resources, and optional extra config like `envFrom`.
- `service`: expose the container port(s) defined above.
- `persistence`: configure PVCs (type, size, storageClass, mount paths).
- `ingress`: default to disabled; when enabling, follow Cloudflare Tunnel annotations or other ingress class conventions already in the repo.
- Any additional chart-specific sections (e.g., `configMaps`, `secrets`, `envFrom`) live alongside the blocks above.

Keep secrets out of Git—reference existing Kubernetes Secrets via `valueFrom` or mount points instead.

## 3. Create the Argo CD Application
The Application manifest glues everything together. Base structure:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
spec:
  project: default
  sources:
    - chart: <helm-chart-name>
      repoURL: <helm-repo-url>
      targetRevision: <chart-version>
      helm:
        valueFiles:
          - $values/apps/<app-name>/<app-name>-values-production.yaml
    - repoURL: 'ssh://192.168.5.80:23231/nexoflow-k8s-apps'
      targetRevision: HEAD
      ref: values
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: '<app-name>'
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true # include when the chart benefits from SSA
```

Notes:
- The first source points to the upstream chart (e.g., `app-template`, `calcom`, `n8n`). Update `chart`, `repoURL`, and `targetRevision` as needed.
- The second source references this repo with `ref: values` so Argo CD can load the values file from Git.
- Namespace is usually the app name, but adjust if an app needs to live elsewhere.

## 4. Register the app with Argo CD
Because `bootstrap/root-app.yaml` already points Argo CD at the `apps/` directory with `recurse: true`, simply committing the new folder is enough—no extra wiring required.

After pushing, run `argocd app sync <app-name>` or wait for automated sync.

---
Following this pattern keeps every app consistent, makes diffs predictable, and lets Argo CD manage them uniformly.
