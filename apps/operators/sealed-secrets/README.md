# sealed-secrets

Bitnami [sealed-secrets](https://github.com/bitnami-labs/sealed-secrets) controller.
Lets us commit **encrypted** secrets to Git: a `SealedSecret` can only be
decrypted by the controller running in *this* cluster, so the YAML is safe in
the repo while the plaintext `Secret` is materialised in-cluster.

| | |
|---|---|
| Argo app | `apps/operators/sealed-secrets/sealed-secrets-operator.yaml` (project `operators`) |
| Chart | `sealed-secrets` `2.18.6` (controller appVersion `0.37.0`) |
| Namespace | **`kube-system`** |
| Controller name | `sealed-secrets-controller` |
| `kubeseal` CLI | match the controller appVersion (`0.37.0`) |

## Why `kube-system` and not a dedicated namespace

First attempt installed into a fresh `sealed-secrets` namespace. On this
single-node k3s the kubelet wedges on the auto-published `kube-root-ca.crt`
ConfigMap for a **brand-new** namespace (`MountVolume.SetUp failed ...
configmap "kube-root-ca.crt" not found`), so the controller pod never starts —
recreating the pod doesn't help. `kube-system` already has a long-stable CA
ConfigMap and is sealed-secrets' upstream default, so we install there. It also
matches `kubeseal`'s defaults, so sealing needs no `--controller-*` flags.

## Sealing a secret

```bash
# from a live Secret (e.g. rotating a value):
kubectl -n <ns> get secret <name> -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > path/to/<name>-sealedsecret.yaml
# commit the SealedSecret; Argo applies it; the controller unseals it.
```

Example in this repo: `src/hhccia-v2/hhccia-core-sealedsecret.yaml`.

## Adopting a pre-existing (unmanaged) Secret

The controller refuses to overwrite a `Secret` it doesn't own
(`already exists and is not managed by SealedSecret`). A metadata-only nudge is
ignored (`update suppressed, no changes in spec`). To hand an existing
out-of-band Secret over to a new SealedSecret:

```bash
kubectl -n <ns> delete secret <name>
kubectl -n kube-system rollout restart deploy/sealed-secrets-controller
# controller reconciles all SealedSecrets on startup and recreates <name>,
# now with an ownerReference to the SealedSecret.
```

## ⚠️ Master key — back it up

The controller generates an RSA keypair stored as a labelled TLS Secret in
`kube-system`. **If it is lost, every committed SealedSecret becomes
permanently undecryptable.** Back it up off-cluster (sealing keys are renewed
over time, so re-back-up periodically; the label catches all of them):

```bash
kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > master-key.yaml
# store master-key.yaml OFFLINE / in a password manager — never in Git.
```

### Restore (rebuilt cluster / lost controller)

```bash
kubectl apply -f master-key.yaml                 # restore the keypair first
kubectl -n kube-system rollout restart deploy/sealed-secrets-controller
# the controller adopts the restored key and can decrypt existing SealedSecrets.
```
