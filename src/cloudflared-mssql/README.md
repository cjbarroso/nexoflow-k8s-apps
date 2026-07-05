# cloudflared-mssql

A dedicated **Cloudflare Tunnel** connector that exposes an on-prem **MSSQL**
server (TDS over TCP 1433) — living at a LAN IP *outside* the cluster — behind a
Cloudflare hostname, **without opening any inbound port** on the router.

## Why this is separate from `apps/operators/cloudflared`

That app is the strrl **`cloudflare-tunnel-ingress-controller`**: it turns
Kubernetes **Ingress** objects into public hostnames over a tunnel it manages.
It only speaks **HTTP/HTTPS/WebSocket**. MSSQL speaks **TDS over raw TCP**, which
the HTTP tunnel (and Cloudflare's orange-cloud proxy) cannot carry. So we run a
second, plain `cloudflared` with its **own** tunnel and a locally-managed
`config.yaml` that declares a raw-TCP ingress rule. The two tunnels are fully
independent.

## Traffic path

```
SSMS / sqlcmd  ──►  cloudflared access tcp (your laptop, localhost:1433)
                        │  authenticated to Cloudflare Access
                        ▼
                  Cloudflare edge  ──► tunnel ──►  cloudflared-mssql pod (cluster)
                                                        │  tcp://<MSSQL_LAN_IP>:1433
                                                        ▼
                                                  MSSQL server (LAN)
```

Because the client side needs `cloudflared` (or WARP), the database is **never**
directly reachable from the internet, and access is gated by a Cloudflare Access
policy scoped to your identity.

## Files

| File | Purpose |
|---|---|
| `configmap.yaml` | `config.yaml` — the tunnel UUID + the `tcp://<MSSQL_LAN_IP>:1433` ingress rule |
| `deployment.yaml` | 2× hardened `cloudflared` connectors (outbound-only) |
| `credentials-sealedsecret.yaml` | tunnel `credentials.json`, sealed (⚠️ placeholder until you generate it) |
| `../../apps/operators/cloudflared-mssql/app.yaml` | the Argo CD Application |

---

## One-time setup

You need the `cloudflared` CLI logged in to the same Cloudflare account
(`cloudflared tunnel login`), and `kubeseal` matching the controller
(`0.37.0`, see `apps/operators/sealed-secrets/README.md`).

### 1. Create the tunnel

```bash
cloudflared tunnel create mssql-tcp
# → prints the tunnel UUID and writes ~/.cloudflared/<UUID>.json (credentials.json)
```

### 2. Route the DNS record to the tunnel

```bash
cloudflared tunnel route dns mssql-tcp mssql-srn.irupeconsultores.com
# creates the proxied CNAME <UUID>.cfargotunnel.com in Cloudflare DNS
```

### 3. Fill in the two placeholders

- `configmap.yaml` → set `tunnel: <TUNNEL_UUID>` and
  `service: tcp://<MSSQL_LAN_IP>:1433` (the LAN IP:port of the MSSQL box; use
  `1433` unless it listens elsewhere).

### 4. Seal the credentials

```bash
kubectl create secret generic cloudflared-mssql-creds \
  --namespace cloudflared \
  --from-file=credentials.json=$HOME/.cloudflared/<UUID>.json \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller \
           --controller-namespace kube-system -o yaml \
> src/cloudflared-mssql/credentials-sealedsecret.yaml
```

### 5. Gate it with Cloudflare Access (Zero Trust) — do NOT skip

In the Zero Trust dashboard → **Access → Applications → Add → Self-hosted**:

- **Application domain:** `mssql-srn.irupeconsultores.com`
- **Policy:** Allow → *Emails* → `carlos.barroso@goconvey.com` (add others as
  needed). Optionally require WARP / device posture.

Without a policy, anyone who runs `cloudflared access tcp` against the hostname
could reach the login prompt. With it, only your identity establishes the tunnel
session.

### 6. Commit & let Argo sync

```bash
git add src/cloudflared-mssql apps/operators/cloudflared-mssql
git commit
git push
```

The root app-of-apps discovers `apps/operators/cloudflared-mssql/app.yaml`, and
the connectors register with the edge. Check:

```bash
kubectl -n cloudflared get pods -l app=cloudflared-mssql
kubectl -n cloudflared logs -l app=cloudflared-mssql | grep -i "registered\|connection"
```

---

## Connecting from your machine

```bash
# Terminal 1 — open the local proxy (prompts for Access login on first run):
cloudflared access tcp --hostname mssql-srn.irupeconsultores.com --url localhost:1433
```

Then point your client at `localhost:1433`:

- **SSMS / Azure Data Studio:** Server `localhost,1433`, enable
  *Encrypt* + *Trust server certificate*.
- **sqlcmd:** `sqlcmd -S localhost,1433 -U <user> -C`

To skip the interactive terminal, install the **WARP** client and use Cloudflare
Access *service tokens* / device enrollment instead — same tunnel, no per-session
command.

## Notes

- **No router port is opened** — the connectors dial *out* to the Cloudflare edge
  (443/7844).
- Egress in the `cloudflared` namespace is unrestricted (same as the other
  namespaces), so the pod reaches both the edge and the MSSQL LAN IP; no
  NetworkPolicy change is required.
- The image tag is pinned and Renovate bumps it; `no-autoupdate` keeps cloudflared
  from self-updating out from under the pin.
- Rotating the tunnel: recreate it, re-run steps 1–4, commit. Delete the old
  tunnel (`cloudflared tunnel delete mssql-tcp`) once the new connectors are up.
