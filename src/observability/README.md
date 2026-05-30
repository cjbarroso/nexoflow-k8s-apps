# src/observability — raw manifests (secrets)

Applied by the `observability-secrets` Argo app (`apps/observability/observability-secrets.yaml`).

| File | Purpose |
|------|---------|
| `grafana-secrets.example.yaml` | PLACEHOLDER template (excluded from Argo). Keys Grafana needs. |
| `grafana-secrets-sealedsecret.yaml` | The real, **sealed** secret. **You create this** (steps below). Safe to commit. |
| `prometheus-hc-ping.example.yaml` | PLACEHOLDER template (excluded from Argo). The healthchecks.io ping URL for the Prometheus dead-man's switch. |
| `prometheus-hc-ping-sealedsecret.yaml` | The real, **sealed** ping-URL secret. **You create this** (steps below). Safe to commit. |

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

### 2b. Seal the healthchecks.io ping-URL secret (Prometheus dead-man's switch)

Create a healthchecks.io check first (note its **ping URL**, `https://hc-ping.com/<uuid>`),
then seal it. Alertmanager mounts this and pings the URL every 5 min while Prometheus
is alive; if the pings stop, healthchecks.io alerts you.

```bash
kubectl create secret generic prometheus-hc-ping -n observability \
  --from-literal=url='https://hc-ping.com/<your-uuid>' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller \
    --controller-namespace kube-system -o yaml \
> src/observability/prometheus-hc-ping-sealedsecret.yaml
```

Commit it. Until it exists, the `prometheus-alertmanager` pod stays pending on the
missing Secret mount — expected. On the **healthchecks.io** side, set the check's
**period** a bit above the 5-min ping (e.g. period `10m`, grace `5m`) so a single
delayed ping doesn't false-alarm but a real outage surfaces within ~15 min.

### 3. (done) Chart versions

Already pinned + validated: loki `7.0.0`, alloy `1.8.2`, grafana `10.5.15`.
To bump later: `helm repo update grafana && helm search repo grafana/<chart>`,
then re-template with the values file before changing `targetRevision`.

### 4. Sync

```bash
argocd app sync loki alloy grafana prometheus observability-secrets
```
