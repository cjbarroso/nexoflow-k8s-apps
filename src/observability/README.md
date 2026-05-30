# src/observability — raw manifests (secrets)

Applied by the `observability-secrets` Argo app (`apps/observability/observability-secrets.yaml`).

| File | Purpose |
|------|---------|
| `grafana-secrets.example.yaml` | PLACEHOLDER template (excluded from Argo). Keys Grafana needs. |
| `grafana-secrets-sealedsecret.yaml` | The real, **sealed** secret. **You create this** (steps below). Safe to commit. |

## First-time bring-up

### 1. Create the Authentik OAuth application

In Authentik (`https://auth.cjbarroso.com`), create an **OAuth2/OpenID provider**
+ **application** with slug `grafana`:

- Redirect URI: `https://logs.cjbarroso.com/login/generic_oauth`
- Scopes: `openid`, `profile`, `email`
- Copy the generated **Client ID** and **Client Secret**.

Sanity-check the endpoint URLs baked into `grafana-values.yaml` against:
`https://auth.cjbarroso.com/application/o/grafana/.well-known/openid-configuration`

### 2. Seal the Grafana secret

Fill real values into a Secret and seal it with the in-cluster controller
(`sealed-secrets-controller` in `kube-system`):

```bash
kubectl create secret generic grafana-secrets -n observability \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<a-strong-password>' \
  --from-literal=oidc-client-id='<authentik-client-id>' \
  --from-literal=oidc-client-secret='<authentik-client-secret>' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller \
    --controller-namespace kube-system -o yaml \
> src/observability/grafana-secrets-sealedsecret.yaml
```

Commit `grafana-secrets-sealedsecret.yaml`. Argo applies it, the controller
decrypts it into the `grafana-secrets` Secret, and the Grafana pod starts.

### 3. (done) Chart versions

Already pinned + validated: loki `7.0.0`, alloy `1.8.2`, grafana `10.5.15`.
To bump later: `helm repo update grafana && helm search repo grafana/<chart>`,
then re-template with the values file before changing `targetRevision`.

### 4. Sync

```bash
argocd app sync loki alloy grafana observability-secrets
```
