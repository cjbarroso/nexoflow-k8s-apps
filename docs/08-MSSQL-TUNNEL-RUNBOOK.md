# MSSQL Tunnel — Connect Runbook

How to reach the on-prem **MSSQL** server through the Cloudflare Tunnel from your
workstation. The database lives at `192.168.5.132:1433` on the remote LAN and is
**not** directly exposed to the internet — you connect via an Access-gated
tunnel. Deployment details: `src/cloudflared-mssql/README.md`.

| | |
|---|---|
| Public hostname | `mssql-srn.irupeconsultores.com` |
| Backend | `192.168.5.132:1433` (TDS / raw TCP) |
| Tunnel | `mssql-tcp` (UUID `98b16c57-a8ad-4540-ba20-f71268ea1242`) |
| Cluster app | `cloudflared-mssql` (ns `cloudflared`, Argo project `operators`) |
| Auth gate | Cloudflare Access self-hosted policy on the hostname |

## Prerequisites (one-time)

- `cloudflared` CLI installed and logged in (`cloudflared tunnel login`).
- A SQL client: `sqlcmd`, SSMS, or Azure Data Studio.
- Your identity allowed by the Cloudflare Access policy for the hostname.

---

## Step 1 — Open the local proxy

In a dedicated terminal (leave it running for the whole session):

```powershell
cloudflared access tcp --hostname mssql-srn.irupeconsultores.com --url localhost:1433
```

- On first run it opens a browser for the Cloudflare Access login. Approve with
  your allowed identity.
- The command binds `localhost:1433` and forwards it over the tunnel. It stays in
  the foreground; closing it drops the connection.
- Use a different local port (`--url localhost:14330`) if `1433` is taken by a
  local SQL Server — then point your client at that port instead.

## Step 2 — Connect your SQL client

Point the client at **`localhost,1433`** (not the public hostname — that's what
the proxy listens on locally). Always enable encryption.

**sqlcmd**

```powershell
sqlcmd -S "localhost,1433" -U <your_user> -C -Q "SELECT @@VERSION"
```

- `-C` trusts the server certificate; `-U`/`-P` for SQL auth (omit `-P` to be
  prompted — don't put passwords in shell history).

**SSMS / Azure Data Studio**

- Server name: `localhost,1433`
- Authentication: SQL Server Authentication (your DB login)
- Encryption: **Encrypt = Mandatory/True**, **Trust server certificate = True**

---

## Verifying reachability (no DB credentials needed)

If a connection misbehaves, isolate *where* it breaks before touching
credentials. Run these with the proxy from Step 1 up:

**TCP path** — proves the tunnel carries traffic to the DB port:

```powershell
Test-NetConnection -ComputerName localhost -Port 1433
# TcpTestSucceeded : True  => path is up
```

**TDS/SQL layer** — proves SQL Server itself is answering. A *login-failed* reply
is SUCCESS (the server negotiated the protocol and rejected a bogus user):

```powershell
sqlcmd -S "localhost,1433" -U "probe_reachability_test" -P "x" -C -l 8 -Q "SELECT 1"
# "Login failed for user 'probe_reachability_test'"  => SQL Server reachable
```

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| Browser login loops / "not allowed" | Access policy doesn't include you | Zero Trust → Access → Applications → the `mssql-srn` app → add your email |
| `Test-NetConnection` fails, proxy running | Connectors down or not registered | `kubectl -n cloudflared get pods -l app=cloudflared-mssql`; `kubectl -n cloudflared logs -l app=cloudflared-mssql --tail=30` (look for `Registered tunnel connection`) |
| TCP ok, but SQL client times out | Connector can't reach `192.168.5.132:1433` (LAN routing/firewall) | Check connector logs for `dial tcp 192.168.5.132:1433`; verify the k3s node can route to that subnet and MSSQL allows the source |
| `cloudflared` connect refused / DNS | Hostname/DNS route drift | Confirm the CNAME points at `<UUID>.cfargotunnel.com`; re-run `cloudflared tunnel route dns mssql-tcp mssql-srn.irupeconsultores.com` |
| `code 10000 Authentication error` on tunnel ops | Stale/wrong-account `~/.cloudflared/cert.pem` | Move it aside and `cloudflared tunnel login` again, selecting the account that owns the zone |

## Health checks (cluster side)

```powershell
kubectl -n argocd get application cloudflared-mssql
kubectl -n cloudflared get pods -l app=cloudflared-mssql
kubectl -n cloudflared logs -l app=cloudflared-mssql --tail=40 | Select-String "Registered|error|dial"
```
