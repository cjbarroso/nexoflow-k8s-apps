# Cloudflare Access Client Proxies as Windows Services

The MSSQL and Kubernetes-API tunnels are reached from a workstation via
`cloudflared access tcp` proxies that bind `localhost:1433` / `localhost:6443`.
This runbook makes those two proxies **persistent Windows services** (auto-start
at boot, restart on crash) using **WinSW**, authenticated non-interactively with a
**Cloudflare Access service token**.

> The server-side tunnel connectors already run 24/7 in the cluster (Argo apps
> `cloudflared-mssql`, `cloudflared-k8s-api`). This runbook is only about the
> **client** proxies. Related: `docs/08-MSSQL-TUNNEL-RUNBOOK.md`,
> `src/cloudflared-k8s-api/README.md`.

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
  directory ACL to `SYSTEM` + `Administrators`, and the token is passed via env
  vars so it never shows on the process command line.
- These services keep a **standing path to the DB and the k8s control plane** on
  this box. If it's a roaming laptop, consider installing only the MSSQL service
  and keeping the k8s API on-demand. **Revoke the service token** immediately if
  the machine is lost — that instantly kills both proxies' Access auth.

---

## Setup

### 1. Create the Access service token

Zero Trust → **Access → Service Auth → Service Tokens → Create Service Token**
(name e.g. `srn-workstation`). Copy the **Client ID** and **Client Secret** (the
secret is shown once).

### 2. Allow the token on BOTH Access apps

For each app (`mssql-srn.irupeconsultores.com`, `kubernetes-srn.irupeconsultores.com`):
Access → Applications → the app → **Policies** → add a policy with
Action = **Service Auth**, Include → **Service Token** → the token you created.
(Keep your existing identity/email policy for interactive use.)

### 3. Files (staged at `C:\ProgramData\cloudflared-access\`)

| File | Purpose |
|---|---|
| `cloudflared.exe` | stable copy of the binary (per-user WinGet path isn't reachable by a LocalSystem service) |
| `cloudflared-access-mssql.xml` | WinSW def → `mssql-srn` → `localhost:1433` |
| `cloudflared-access-k8s.xml` | WinSW def → `kubernetes-srn` → `localhost:6443` |
| `install-services.ps1` | elevated installer (downloads WinSW, installs + starts both, locks ACL) |

WinSW service definition (MSSQL shown; the k8s one is identical with `6443` and
the `kubernetes-srn` hostname):

```xml
<service>
  <id>cloudflared-access-mssql</id>
  <name>Cloudflared Access - MSSQL (mssql-srn)</name>
  <executable>%BASE%\cloudflared.exe</executable>
  <arguments>access tcp --hostname mssql-srn.irupeconsultores.com --url localhost:1433 --loglevel info</arguments>
  <env name="TUNNEL_SERVICE_TOKEN_ID" value="__FILL_SERVICE_TOKEN_ID__"/>
  <env name="TUNNEL_SERVICE_TOKEN_SECRET" value="__FILL_SERVICE_TOKEN_SECRET__"/>
  <startmode>Automatic</startmode>
  <onfailure action="restart" delay="10 sec"/>
  <resetfailure>1 hour</resetfailure>
  <log mode="roll-by-size"><sizeThreshold>10240</sizeThreshold><keepFiles>3</keepFiles></log>
</service>
```

### 4. Fill in the token + install

1. Edit both `.xml` files, replacing `__FILL_SERVICE_TOKEN_ID__` and
   `__FILL_SERVICE_TOKEN_SECRET__` with the token values from step 1.
2. In an **elevated** PowerShell:

   ```powershell
   & C:\ProgramData\cloudflared-access\install-services.ps1
   ```

   It refuses to proceed if the placeholders are still present, downloads WinSW
   `v2.12.0`, installs + starts both services, and locks the directory ACL.

---

## Verify

```powershell
Get-Service cloudflared-access-mssql, cloudflared-access-k8s
Test-NetConnection localhost -Port 1433   # TcpTestSucceeded : True
Test-NetConnection localhost -Port 6443   # TcpTestSucceeded : True
```

Then use them exactly as before — the proxies are always listening:

```powershell
sqlcmd -S "localhost,1433" -U <user> -C -Q "SELECT @@VERSION"
# kubectl via a kubeconfig whose server is https://127.0.0.1:6443
```

## Logs & operations

```powershell
Get-Content C:\ProgramData\cloudflared-access\cloudflared-access-k8s.out.log -Tail 30
Restart-Service cloudflared-access-mssql
```

## Rotate the service token

Create a new token, update both apps' policies, edit the two `.xml` files, then
`Restart-Service` both. Delete the old token in the dashboard.

## Uninstall

```powershell
foreach ($s in 'cloudflared-access-mssql','cloudflared-access-k8s') {
  & "C:\ProgramData\cloudflared-access\$s.exe" stop
  & "C:\ProgramData\cloudflared-access\$s.exe" uninstall
}
```

## Notes

- WinSW needs one exe per service, named to match its XML — the installer copies
  `WinSW-x64.exe` to `cloudflared-access-mssql.exe` / `cloudflared-access-k8s.exe`.
- Services run as `LocalSystem` by default; service-token auth needs no user
  profile / `cert.pem`, so LocalSystem is fine.
- After a `cloudflared` upgrade, re-copy the new `cloudflared.exe` into the folder
  and `Restart-Service` both.
