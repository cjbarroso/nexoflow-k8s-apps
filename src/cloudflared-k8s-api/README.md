# cloudflared-k8s-api

A dedicated **Cloudflare Tunnel** connector that exposes the **Kubernetes API
server** (TLS-over-TCP) behind `kubernetes-srn.irupeconsultores.com`, **without
opening any inbound port** on the router.

## Why this is separate

- Not the strrl **`cloudflare-tunnel-ingress-controller`** (`apps/operators/
  cloudflared`) — that only carries HTTP/S. The API is raw TCP with mTLS.
- Not the **MSSQL** tunnel (`src/cloudflared-mssql`) — kept as its own tunnel so
  the API server has isolated credentials and its own Access policy (bigger blast
  radius warrants isolation).

## Traffic path & why it's safe

```
kubectl (kubeconfig server https://127.0.0.1:6443)
   → cloudflared access tcp (your laptop, localhost:6443)
        │  1) authenticated to Cloudflare Access (identity gate)
        ▼
   Cloudflare edge → tunnel → cloudflared-k8s-api pod
        │  2) tcp://kubernetes.default.svc:443 (ClusterIP 10.43.0.1)
        ▼
   kube-apiserver  (mTLS terminates HERE, not at cloudflared)
```

**Two independent auth layers** must both pass:

1. **Cloudflare Access** — a self-hosted Access policy gates who can even open the
   TCP session.
2. **Kubernetes mTLS** — your kubeconfig's client cert/token authenticates to the
   apiserver. TLS is negotiated end-to-end; cloudflared only pipes opaque bytes
   and never sees the plaintext or your credentials.

## Future-proof for HA (1 → 3 nodes)

The route targets the in-cluster `kubernetes` Service (`ClusterIP 10.43.0.1:443`),
not a node IP. That Service is backed by every control-plane node's apiserver, so
adding nodes needs **no change here** — kube-proxy load-balances automatically.

## Files

| File | Purpose |
|---|---|
| `configmap.yaml` | `config.yaml` — tunnel UUID + the `tcp://kubernetes.default.svc:443` rule |
| `deployment.yaml` | 2× hardened `cloudflared` connectors (outbound-only, no SA token) |
| `credentials-sealedsecret.yaml` | tunnel `credentials.json`, sealed (⚠️ placeholder until generated) |
| `../../apps/operators/cloudflared-k8s-api/app.yaml` | the Argo CD Application |

---

## One-time setup

Needs the `cloudflared` CLI logged in (`cloudflared tunnel login`) and `kubeseal`
matching the controller (`0.37.0`). Run kubeseal on the `nexoflow` kube context.

### 1. Create the tunnel

```bash
cloudflared tunnel create kubernetes-api
# → prints the tunnel UUID and writes ~/.cloudflared/<UUID>.json
```

### 2. Route the DNS record

```bash
cloudflared tunnel route dns kubernetes-api kubernetes-srn.irupeconsultores.com
```

### 3. Fill in the UUID

`configmap.yaml` → set `tunnel: <TUNNEL_UUID>`.

### 4. Seal the credentials (PowerShell)

```powershell
$tmp = "$env:TEMP\cf-k8s-secret.yaml"
kubectl create secret generic cloudflared-k8s-api-creds `
  --namespace cloudflared `
  --from-file=credentials.json=$env:USERPROFILE\.cloudflared\<UUID>.json `
  --dry-run=client -o yaml | Out-File -Encoding utf8 $tmp
kubeseal --controller-name sealed-secrets-controller `
         --controller-namespace kube-system -f $tmp -o yaml `
  | Out-File -Encoding utf8 src\cloudflared-k8s-api\credentials-sealedsecret.yaml
Remove-Item $tmp
```

### 5. Add a STRICT Cloudflare Access policy — do NOT skip

Zero Trust → **Access → Applications → Add → Self-hosted**:

- **Application domain:** `kubernetes-srn.irupeconsultores.com`
- **Policy:** Allow → *Emails* → your address only. This is the API server —
  strongly prefer **requiring WARP / device posture** and a **short session
  duration**, and consider a service token for automation instead of broad email
  allow.

### 6. Commit & let Argo sync

```bash
git add src/cloudflared-k8s-api apps/operators/cloudflared-k8s-api
git commit && git push
```

Verify:

```bash
kubectl -n cloudflared get pods -l app=cloudflared-k8s-api
kubectl -n cloudflared logs -l app=cloudflared-k8s-api | grep -i "Registered tunnel connection"
```

---

## Connecting with kubectl

**1. Open the local proxy** (leave running; prompts for Access login first time):

```powershell
cloudflared access tcp --hostname kubernetes-srn.irupeconsultores.com --url localhost:6443
```

**2. Use a kubeconfig pointed at the local proxy.** Copy your existing context and
change only the server URL to `https://127.0.0.1:6443` (the apiserver cert has
`127.0.0.1` + `localhost` SANs, so TLS validates; keep the same CA + client cert):

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-srn"
kubectl config set-cluster nexoflow --server=https://127.0.0.1:6443
kubectl get nodes
```

If you copy the whole `nexoflow` context, edit its `cluster.server` to
`https://127.0.0.1:6443` and leave `certificate-authority-data` and the user
client-cert untouched.

## Notes

- **No router port opened** — connectors dial out to the Cloudflare edge.
- The connector needs **no Kubernetes RBAC** — it forwards an opaque TLS stream;
  the SA token is not mounted.
- Because mTLS is end-to-end, `--insecure-skip-tls-verify` is **never** needed and
  must not be used.
- Rotating the tunnel: recreate it, re-run steps 1–4, commit; then
  `cloudflared tunnel delete kubernetes-api` once the new connectors are up.
