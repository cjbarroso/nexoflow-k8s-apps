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

## Backups And Upgrades

The Velero daily filesystem schedule includes the `vault` namespace. Keep the
unseal keys and root-token recovery material offline as well, because they are
not recoverable from the Kubernetes objects alone.

Vault uses the chart's `OnDelete` StatefulSet strategy. Back up Vault before
changing the image or chart version, upgrade standby nodes before the active
node, and unseal replacement pods when Shamir sealing is in use.
