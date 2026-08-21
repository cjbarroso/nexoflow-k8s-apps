# Vault Runbook

Vault is deployed by `apps/vault/app.yaml` into the `vault` namespace as a
three-node Raft cluster. It has no public Ingress. The internal API endpoints
are:

- `https://vault-active.vault.svc.cluster.local:8200` - active node only; preferred for clients
- `https://vault.vault.svc.cluster.local:8200` - all Vault nodes through the ClusterIP service

The service-side NetworkPolicy permits ports 8200 and 8201 from every namespace.
A client namespace with its own default-deny egress policy must add an egress
rule for Vault and DNS separately.

## First Bootstrap

Use the required cluster context and wait for all three pods to be running:

```bash
kubectl config use-context nexoflow-cf
kubectl -n vault get pods -l app.kubernetes.io/name=vault -w
```

Initialize `vault-0` once. Save every unseal key and the initial root token in
an offline password manager. They are intentionally not stored in Kubernetes or
Git:

```bash
kubectl -n vault exec vault-0 -- env VAULT_ADDR=https://vault-0.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault operator init -key-shares=5 -key-threshold=3
```

Use three different key shares to unseal each pod. Repeat the command three
times per pod, replacing `<UNSEAL_KEY>` each time:

```bash
kubectl -n vault exec vault-0 -- env VAULT_ADDR=https://vault-0.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault operator unseal <UNSEAL_KEY>
kubectl -n vault exec vault-1 -- env VAULT_ADDR=https://vault-1.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault operator unseal <UNSEAL_KEY>
kubectl -n vault exec vault-2 -- env VAULT_ADDR=https://vault-2.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault operator unseal <UNSEAL_KEY>
```

The Raft `retry_join` configuration should join `vault-1` and `vault-2`
automatically after `vault-0` is initialized. Verify the peer list with the
root token:

```bash
kubectl -n vault exec vault-0 -- env VAULT_ADDR=https://vault-0.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt VAULT_TOKEN=<ROOT_TOKEN> vault operator raft list-peers
```

If a peer did not join automatically, join it once and then unseal it:

```bash
kubectl -n vault exec vault-1 -- env VAULT_ADDR=https://vault-1.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault operator raft join https://vault-0.vault-internal:8200
kubectl -n vault exec vault-2 -- env VAULT_ADDR=https://vault-2.vault-internal:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault operator raft join https://vault-0.vault-internal:8200
```

Enable the file audit device after initialization. The command is idempotent
only if the audit device already exists, so check `vault audit list` first:

```bash
kubectl -n vault exec vault-0 -- env VAULT_ADDR=https://vault-active.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt VAULT_TOKEN=<ROOT_TOKEN> vault audit enable file file_path=/vault/audit/audit.log
```

## Client Trust

The generated `vault-tls` Secret contains the server key and must remain in the
Vault namespace. Clients need only the CA certificate. Extract `ca.crt` without
copying the private key:

```powershell
$ca = kubectl --context nexoflow-cf -n vault get secret vault-tls -o jsonpath='{.data.ca\.crt}'
[System.IO.File]::WriteAllBytes('vault-ca.crt', [Convert]::FromBase64String($ca))
```

Install that CA certificate in the client workload's namespace according to
the workload's configuration, then set:

```text
VAULT_ADDR=https://vault-active.vault.svc.cluster.local:8200
VAULT_CACERT=/path/to/vault-ca.crt
```

Do not use `VAULT_SKIP_VERIFY` for normal clients. The Vault Agent Injector and
CSI provider are disabled in the initial deployment; enable them only through
a deliberate follow-up change with workload-specific policies.

## Vault Secrets Operator

The HashiCorp Vault Secrets Operator is installed by
`apps/operators/vault-secrets-operator/app.yaml` in the
`vault-secrets-operator` namespace. The operator's default Vault connection and
authentication resources are intentionally disabled. Workloads must declare
their own namespaced connection and authentication resources so Vault policies
remain workload-specific.

The CA Secret referenced by `caCertSecretRef` must contain only `ca.crt`. Do not
copy the `vault-tls` Secret or the CA private key out of the `vault` namespace.
The following is a template for a workload namespace; replace the placeholders
and commit it with that workload's manifests:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: <WORKLOAD_NAMESPACE>
spec:
  address: https://vault-active.vault.svc.cluster.local:8200
  caCertSecretRef: vault-ca
  tlsServerName: vault-active.vault.svc.cluster.local
  skipTLSVerify: false
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: <WORKLOAD_NAMESPACE>
spec:
  vaultConnectionRef: vault-connection
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: <VAULT_KUBERNETES_ROLE>
    serviceAccount: <WORKLOAD_SERVICE_ACCOUNT>
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: workload-secrets
  namespace: <WORKLOAD_NAMESPACE>
spec:
  vaultAuthRef: vault-auth
  mount: kv
  type: kv-v2
  path: <VAULT_KV_PATH>
  refreshAfter: 1m
  destination:
    name: workload-secrets
    create: true
```

The Vault Kubernetes auth method and the role named by `VaultAuth` must be
configured in Vault before the custom resources can become ready. Bind each
role to only the intended Kubernetes ServiceAccount and namespace, and grant it
read access only to the corresponding KV path. The generated Kubernetes Secret
is the only secret object consumed by the workload; secret values remain in
Vault and must not be committed to Git.

## Day-To-Day Administration (No Root Token)

The initial root token was revoked on 2026-08-21 after the VSO migration.
All routine Vault work uses the scoped **`migrator`** policy, authenticated
via Kubernetes auth bound to SA `vault` in namespace `vault` — there is no
stored credential anywhere:

```bash
# Run from inside vault-0; mints a 1h token with only the migrator policy
kubectl -n vault exec vault-0 -- sh -c '
  export VAULT_ADDR=https://vault-active.vault.svc.cluster.local:8200 \
         VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt
  JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  VT=$(vault write auth/kubernetes/login jwt="$JWT" role=migrator | awk "/^token /{print \$2}")
  export VAULT_TOKEN=$VT
  # ... vault commands ...
'
```

`migrator` can: read/write all KV under `nexoflow/*`, create/delete ACL
policies, create/delete Kubernetes auth roles. It cannot: touch mounts, auth
method config, other namespaces' KV, or tokens. Parse the login response with
awk on the table output — `-format=json` + sed is fragile.

### Emergency Root Recovery

If root privileges are ever needed again (mount changes, disaster recovery),
mint a new one from the unseal shares stored in Vaultwarden:

```bash
kubectl -n vault exec vault-0 -- vault operator generate-root -init   # follow prompts
# feed 3 of 5 unseal keys; decode the final token with the OTP
```

Revoke any emergency root immediately after use.

## Adding A New Secret (Quick Reference)

**Namespace already has a `vault-secrets.yaml` stack:**

1. Write the value from inside vault-0 (migrator login, see above):
   `vault kv put nexoflow/<NS>/<name> KEY='value'`
2. Append one `VaultStaticSecret` block to `src/<app>/vault-secrets.yaml`
   (`vaultAuthRef: <ns-auth>`, `destination.name` = Secret name workloads
   read; add `rolloutRestartTargets` only if env vars must refresh).
3. Commit, push, `task argo:sync APP=<app>`. Done.

**Brand-new namespace checklist:**

1. Vault: policy `<NS>-ro` (read on `nexoflow/data/<NS>/*`) + k8s role
   `<NS>` bound to SA `default` in that namespace (both via migrator).
2. Copy the public CA into the ns as Secret `vault-ca`, then declare
   `VaultConnection default` + `VaultAuth <NS>` (**explicit**
   `vaultConnectionRef`) in `src/<app>/vault-secrets.yaml`.
3. Add the `.gitleaksignore` fingerprint for the CA cert line gitleaks
   reports on first commit.
4. If the Argo app uses directory `include:` filters, make sure the new file
   matches (this bit cloudflared once).
5. Commit → sync **root** first if any `apps/**/app.yaml` changed, then the
   child app.

## Raft Snapshot Backups

A nightly CronJob (`vault-snapshot-backup`, 03:30 UTC, namespace `vault`)
takes a native Raft snapshot, encrypts it with **age**, uploads it to R2 at
`s3://velero-backups/vault-snapshots/`, and prunes files older than 7 days.
R2 credentials are materialized by VSO from KV v2 at
`nexoflow/vault/r2-creds`; the job authenticates to Vault via Kubernetes auth
(role `vault-snapshot`, policy `raft-snapshot` = read+sudo on
sys/storage/raft/snapshot only).

Encryption keys: the age PUBLIC key sits in the CronJob spec; the PRIVATE key
lives only in Vaultwarden. A snapshot without that private key is unreadable
to everyone — including us — which is the point.
Vaultwarden item: **"Vault Raft snapshot age PRIVATE key (reinit 2026-08-21)"**
(key attached as a file).

Verify monthly: check recent objects exist (`rclone lsf`) and run one test
restore.

### Restore procedure

1. Fetch + decrypt: `rclone copy r2:velero-backups/vault-snapshots/ .`
   then `age -d -i age.privkey vault-<STAMP>.snap.age > vault.snap`
   (both keys from Vaultwarden).
2. Deploy the `vault` Helm app on the target cluster; initialize + unseal it
   with THROWAWAY keys (any valid init).
3. `kubectl cp vault.snap vault/vault-0:/tmp/` then
   `vault operator raft snapshot restore /tmp/vault.snap`.
4. Pods restart automatically; unseal them with the ORIGINAL shares from
   Vaultwarden (a restored Raft snapshot carries its source cluster's barrier).
5. Revoke the temporary root token from step 2.

## SealedSecrets — RETIRED

The sealed-secrets controller was removed on 2026-08-21 after the full VSO
migration (zero SealedSecret instances remained). The Argo app, chart
resources, RBAC and CRD are gone; `*.example.yaml` placeholders and older doc
sections that mention kubeseal are kept only as historical reference. New
secrets go to Vault via the migrator workflow above. The controller's master
keys remain archived in Vaultwarden solely for recovering values from git
history if ever needed.

## SealedSecret To VSO Migration

Secrets move from SealedSecrets to VSO one namespace at a time. The first pilot
was `planka-admin` (2026-08-21); the pattern below is proven — follow it exactly.

### One-time per namespace

Vault side (root token required; stored offline in Vaultwarden):

```bash
# policy scoped to this namespace's KV prefix
printf 'path "nexoflow/data/<NS>/*" {\n  capabilities = ["read"]\n}' | vault policy write <NS>-ro -
# role bound to SA default in that namespace only
vault write auth/kubernetes/role/<NS> \
  bound_service_account_names=default \
  bound_service_account_namespaces=<NS> \
  policies=<NS>-ro ttl=24h
```

Git side (`src/<app>/vault-secrets.yaml`):

1. Copy the public cluster CA into the namespace as Secret `vault-ca`
   (key `ca.crt`). It is public material — add a `.gitleaksignore` entry with
   the exact fingerprint gitleaks prints (rule `kubernetes-secret-yaml`).
2. Declare `VaultConnection` (name `default`, `caCertSecretRef: vault-ca`),
   `VaultAuth` (role + SA), and one `VaultStaticSecret` per Kubernetes Secret.
3. Delete the corresponding `*-sealedsecret.yaml` files **in the same commit**
   so Argo prunes them atomically — never let a SealedSecret controller and VSO
   fight over the same Secret name.

### Per secret

1. Copy current values verbatim from the live Secret into KV *before* touching
   git (`vault kv put nexoflow/<NS>/<name> k=v ...`) so workloads see no change.
2. Sync, then verify: Secret owner must be `VaultStaticSecret` and value
   lengths must match the originals.
3. `rolloutRestartTargets` on each `VaultStaticSecret` bounces workloads only
   when values actually change (env vars are read once at container start).

### Gotchas learned the hard way (do not relearn)

- **VSO 1.5.0 requires an explicit `spec.vaultConnectionRef`** on `VaultAuth`.
  With `allow-default-globals` enabled there is no same-namespace fallback;
  omitting it fails with the misleading error
  `VaultConnection.secrets.hashicorp.com "default" not found`.
- The destination field is **`spec.destination`**, not `dest`
  (`dest` is External Secrets terminology).
- `kubectl auth can-i` and the connection controller can pass while the client
  factory still cannot resolve the ref — the missing-ref failure looks like an
  RBAC or cache problem but isn't.
- Changing `apps/**/app.yaml` requires syncing the **root** app first: the
  child Application definitions themselves are managed by root. Syncing the
  child alone does not refresh its own spec.
- Argo `selfHeal` reverts out-of-band kubectl changes within seconds. For
  maintenance that needs the real state to drift (scaling down, wiping PVCs),
  suspend auto-sync via a git commit, do the work, restore via another commit.
- Sealed-secrets controller key rotation was disabled (`keyrenewperiod: "0"`,
  chart value is all-lowercase) because monthly rotation silently invalidated
  key backups. Back up ALL keys labeled
  `sealedsecrets.bitnami.com/sealed-secrets-key` in `kube-system` to
  Vaultwarden before relying on any single backup file.

### Migrated secrets

| Namespace | Secret | KV path | Date |
|---|---|---|---|
| planka | planka-admin, planka-oidc, planka-secretkey, planka-db-backup-creds | nexoflow/planka/* | 2026-08-21 |
| monica | monica-secrets (6 keys) | nexoflow/monica/monica | 2026-08-21 |
| sftp | sftp-credentials | nexoflow/sftp/credentials | 2026-08-21 |
| pami | pami-downloader-secrets, pami-downloader-gdrive | nexoflow/pami/* | 2026-08-21 |
| observability | gemini-cost-ro, grafana-secrets, authentik-grafana-ro, alertmanager-notify, alertmanager-incident-bearer, prometheus-hc-ping | nexoflow/observability/* | 2026-08-21 |
| vaultwarden | vaultwarden-smtp | nexoflow/vaultwarden/smtp | 2026-08-21 |
| cloudflared | cloudflare-api-credentials, cloudflared-k8s-api-creds, cloudflared-mssql-creds | nexoflow/cloudflared/* | 2026-08-21 |
| authentik | authentik-db-app, authentik-db-backup-creds, authentik-secrets (was hand-made) | nexoflow/authentik/* | 2026-08-21 |
| hermes2 | incident-webhook, cognee-postgres, cognee-openai, machine-creds (orphan) | nexoflow/hermes2/* | 2026-08-21 |
| hhccia-staging | hhccia-core-secrets | nexoflow/hhccia-staging/core-secrets | 2026-08-21 |
| hhccia-v2 | all 6 prod secrets | nexoflow/hhccia-v2/* | 2026-08-21 |
| calibre-web-automated | cwa-gmail | nexoflow/calibre-web-automated/cwa-gmail | 2026-08-21 |

**Known leftovers:**
- ~~`caldiy` namespace~~: deleted entirely on 2026-08-21 (namespace, Cal.com
  deployment, CNPG cluster + PVCs, sealed secrets; Vault KV copies, policy and
  role purged too). It had been applied manually with no Argo app and no git
  manifests.
- `hermes2/hhccia-machine-creds` has no consumer anywhere; kept in Vault.
- Image-pull secrets (`github-auth` in hhccia-v2/staging) remain
  hand-made dockerconfigjson secrets — candidates for a future decision.

Operational note: when several `VaultStaticSecret`s target the same workload,
creating them in one sync makes `rolloutRestartTargets` bounce it repeatedly.
Planka rode through three quick restarts (liveness probe kills during slow
boots) and settled on its own; for large batches, prefer one VSS per namespace
storing all keys under a single KV path where workloads allow it.

Hand-created plain Secrets (e.g. the old `gemini-cost-ro`) cannot be adopted
in place — VSO refuses with `invalid owner label`. Delete the un-owned Secret;
VSO recreates it immediately from Vault (values are identical, workloads keep
running on loaded env until `rolloutRestartTargets` bounces them).

Still on SealedSecrets: everything else (see `src/**/*sealedsecret*.yaml`),
plus the hand-created `gemini-cost-ro` in `observability` (a prime candidate —
it currently exists nowhere in git). Keep bootstrap-critical secrets sealed
until confident; after a full cluster rebuild, VSO-sourced Secrets only appear
once Vault is initialized and unsealed again (Argo retries until then).

## Backups And Upgrades

The Velero daily filesystem schedule includes the `vault` namespace. Keep the
unseal keys and root-token recovery material offline as well, because they are
not recoverable from the Kubernetes objects alone.

Vault uses the chart's `OnDelete` StatefulSet strategy. Back up Vault before
changing the image or chart version, upgrade standby nodes before the active
node, and unseal replacement pods when Shamir sealing is in use.
