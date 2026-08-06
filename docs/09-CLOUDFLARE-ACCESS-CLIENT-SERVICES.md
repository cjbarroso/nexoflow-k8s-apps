# Cloudflare Access Client Proxies as Windows Services

The MSSQL and Kubernetes-API tunnels are reached from a workstation via
`cloudflared access tcp` proxies that bind `localhost:1433` / `localhost:16443`.
Those two proxies run as **persistent Windows services** (auto-start at boot,
restart on crash) using **WinSW**, authenticated non-interactively with a
**Cloudflare Access service token**.

> The server-side tunnel connectors already run 24/7 in the cluster (Argo apps
> `cloudflared-mssql`, `cloudflared-k8s-api`). This runbook covers only the
> **Cloudflare-side** setup (service token + Access policy). Related:
> `docs/08-MSSQL-TUNNEL-RUNBOOK.md`, `src/cloudflared-k8s-api/README.md`.

> **The client install lives in code.** The Windows service installer/uninstaller,
> its config template, and full client docs are a version-controlled component in
> the personal `computer` repo: **`cloudflared-access/`** (README + `install.ps1` +
> `uninstall.ps1` + `config.example.json`). This runbook no longer carries the
> loose `C:\ProgramData\cloudflared-access\` files — use that component instead.

## Why a service token (the critical detail)

An interactive `cloudflared access tcp` uses a browser-login JWT that **expires**
at the Access policy's session duration — a background service can't re-login, so
it would silently stop working. A **service token** (long-lived Client ID +
Secret) authenticates headlessly and doesn't expire that way.

## Security posture

- Two auth layers still apply: Access (now via service token) **+** the backend's
  own auth (SQL login / kubectl mTLS). The token alone reaches only the login
  prompt.
- The token secret lives in the service XML on disk → the installer restricts the
  install-dir ACL to `SYSTEM` + `Administrators`, and the token is passed via env
  vars so it never shows on the process command line. The secret never enters git
  (it lives only in the component's gitignored `config.json`).
- These services keep a **standing path to the DB and the k8s control plane** on
  this box. If it's a roaming laptop, install only the MSSQL proxy and keep the
  k8s API on-demand. **Revoke the service token** immediately if the machine is
  lost — that instantly kills both proxies' Access auth.

---

## Cloudflare-side setup

### 1. Create the Access service token

Zero Trust → **Access → Service Auth → Service Tokens → Create Service Token**
(name e.g. `srn-workstation`). Copy the **Client ID** and **Client Secret** (the
secret is shown once).

### 2. Allow the token on BOTH Access apps

For each app (`mssql-srn.irupeconsultores.com`, `kubernetes-srn.irupeconsultores.com`):
Access → Applications → the app → **Policies** → add a policy with
Action = **Service Auth**, Include → **Service Token** → the token you created.
(Keep your existing identity/email policy for interactive use.)

---

## Client install & verify

See the **`cloudflared-access/`** component in the `computer` repo. In short: copy
`config.example.json` → `config.json`, paste in the token, then run `install.ps1`
from an elevated PowerShell. Verify with:

```powershell
Get-Service cloudflared-access-mssql, cloudflared-access-k8s
Test-NetConnection localhost -Port 1433    # TcpTestSucceeded : True
Test-NetConnection localhost -Port 16443   # TcpTestSucceeded : True
```

Then use them as usual — the proxies are always listening:

```powershell
sqlcmd -S "localhost,1433" -U <user> -C -Q "SELECT @@VERSION"
# kubectl --context nexoflow-cf  (cluster server https://127.0.0.1:16443)
```

## Rotate the service token

Create a new token, update both apps' policies, edit the component's `config.json`,
re-run `install.ps1`, then delete the old token in the dashboard.
