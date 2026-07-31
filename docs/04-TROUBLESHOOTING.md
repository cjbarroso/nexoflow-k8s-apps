# Troubleshooting & Known Issues

## Application Status

Please be aware of the following application statuses to avoid unnecessary debugging.

### Removed applications

WAHA and Cal.com (both broken, never stabilised) were removed from the repo on
2026-06-11. Their manifests live in git history if ever needed; note that the
historical files contain plaintext credentials that must be treated as burned
(see `.gitleaks.toml` and the CI `validate` workflow that now prevents this).

## Argo CD

### App stuck in OutOfSync

1. Check the app diff: `task argo:diff APP=<name>`
2. Common causes:
   - **CNPG Clusters with ServerSideApply**: webhook defaults inject fields that
     cause a permanent diff. Fix: disable SSA for that app (remove
     `ServerSideApply=true` from the sync options).
   - **Helm chart upgrade changed defaults**: compare rendered manifests with
     `helm template` locally.
   - **Resource excluded from sync**: verify the `exclude` glob in the
     Application source isn't too broad.
3. Force a hard refresh: `argocd app get <name> --hard-refresh`

### App won't sync (comparison error)

- Verify the repo URL and `targetRevision` in the Application manifest.
- If the repo was recently migrated (Soft Serve -> GitHub), ensure
  `bootstrap/root-app.yaml` points to
  `https://github.com/cjbarroso/nexoflow-k8s-apps.git`.
- For private repos, check `bootstrap/repo-secret.yaml` credentials.

### Sync wave ordering

`argocd-internal-config` uses `sync-wave: "1"` so it applies after the root
app. If a new app depends on Argo CM settings (e.g., resource exclusions),
give it a higher sync wave.

## CloudNativePG

### Cluster stuck in "Setting up primary"

- Check the CNPG operator logs: `kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg`
- Verify the barman-cloud plugin is installed (`barman-cloud-plugin` app).
- Ensure the ObjectStore credentials SealedSecret decrypted correctly:
  `kubectl get sealedsecret -n <ns> -o yaml` and check controller logs.

### Backup failures

- Confirm the R2 bucket credentials in the barman ObjectStore secret.
- Check `ScheduledBackup` status: `kubectl get scheduledbackup -n <ns>`
- Velero backups: `velero backup get -n velero`

## SealedSecrets

### SealedSecret won't decrypt

- The controller logs the error: `kubectl logs -n kube-system -l name=sealed-secrets-controller`
- Common cause: the secret was sealed with a different controller key (e.g.,
  after a controller reinstall). Re-seal with the current key:
  ```bash
  kubeseal --controller-namespace kube-system \
           --controller-name sealed-secrets \
           < secret.yaml > sealedsecret.yaml
  ```

## Observability

### Grafana shows "No data"

- Verify Prometheus is the default datasource (fixed in commit `5a1af82`).
- Check Alloy DaemonSet is running on all nodes: `kubectl get pods -n observability -l app.kubernetes.io/name=alloy`
- Loki cross-queries: ensure dashboards reference the datasource by UID, not
  by name (fixed in commit `c1d342e`).

### Missing logs

- Alloy collects from `/var/log/pods`; confirm the hostPath mount exists.
- Check Loki compactor isn't OOMKilled: `kubectl describe pod -n observability -l app=loki`

## Cloudflare Tunnel

### Ingress not routing

- Verify the `cloudflared` controller pod is running:
  `kubectl get pods -n operators -l app.kubernetes.io/name=cloudflare-tunnel-ingress-controller`
- Check the tunnel token SealedSecret decrypted (controller logs show auth errors).
- For the MSSQL or K8s API tunnels, see `docs/08-MSSQL-TUNNEL-RUNBOOK.md`.

### `cloudflared access tcp` disconnects (Windows client)

- See `docs/09-CLOUDFLARE-ACCESS-CLIENT-SERVICES.md` for the Windows service
  setup. The service auto-restarts on failure; check `services.msc` status.

## Vaultwarden

See `docs/05-VAULTWARDEN-UPDATE-NOTES.md` for the full update runbook,
including the stale-checkout workflow and why `kubectl apply` alone is not
durable under GitOps.

## General

### kubectl context

Always use the Cloudflare Tunnel context:

```bash
kubectl config use-context nexoflow-cf
```

The direct LAN context (`nexoflow`) only works on the local network.

### Pre-commit hooks failing

- `gitleaks`: you may have a pattern that looks like a secret. If it's a false
  positive, add an allowlist entry to `.gitleaks.toml`.
- `check-yaml`: multi-document YAML needs `--allow-multiple-documents` (already
  configured in `.pre-commit-config.yaml`).
