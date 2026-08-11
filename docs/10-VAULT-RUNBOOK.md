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

## Backups And Upgrades

The Velero daily filesystem schedule includes the `vault` namespace. Keep the
unseal keys and root-token recovery material offline as well, because they are
not recoverable from the Kubernetes objects alone.

Vault uses the chart's `OnDelete` StatefulSet strategy. Back up Vault before
changing the image or chart version, upgrade standby nodes before the active
node, and unseal replacement pods when Shamir sealing is in use.
