# Vault Auto-Unseal — Evaluation

Status: **evaluation only, nothing implemented**. Written 2026-09-29, after the
expired-certificate incident in `10-VAULT-RUNBOOK.md` exposed how much the
Shamir seal constrains operations.

## 1. Why this came up

Every Vault pod that restarts comes back **SEALED** and stays sealed until a
human supplies 3 of the 5 Shamir shares, per pod. That fact is what made the
September incident harder than it needed to be: the fix for the stale TLS
certificate could not simply be "restart the StatefulSet", because that would
have taken the whole secret store down until someone was available with the
keys. It also means:

- Rolling upgrades, node drains and image bumps are human-gated.
- Recovering from a node reboot needs keys; a simultaneous multi-node reboot
  needs keys *and* ordering care.
- The documented DR restore ends with "unseal with the original shares" —
  performed during an incident, from a password manager that runs **inside the
  cluster being restored**.

What auto-unseal does **not** fix:

- It relocates the root of trust, it does not remove it: you get recovery keys
  instead of unseal keys, and root operations still need them.
- It adds a hard dependency: HashiCorp states that if the seal backend or its
  keys are permanently deleted, **the cluster cannot be recovered, even from
  backups** ([seal concepts](https://developer.hashicorp.com/vault/docs/concepts/seal)).
- It does nothing for confidentiality against a live compromise.
- It does **not** fix the actual defect behind the 19-day outage, which was
  observability — nobody knew Vault was broken.

## 2. Options, judged for THIS cluster

Constraints: 3 bare-metal nodes (homestation/2/3), no cloud account attached,
Cloudflare R2 for backups, keys held in Vaultwarden (in-cluster), 34 consumers
of Vault, single part-time operator.

| Option | Verdict here |
|---|---|
| **Cloud KMS auto-unseal** (`awskms`/`gcpckms`/`azurekeyvault`) | **Disqualified as-is** (no cloud account). The strongest technical option *if* an account already exists — but it makes every Vault restart depend on a third-party account and its billing. |
| **Transit auto-unseal** (second Vault cluster) | **Reject.** HashiCorp's own guidance: it "merely moves the burden of non-automated unseal" to the other cluster ([transit best practices](https://developer.hashicorp.com/vault/docs/configuration/seal/transit-best-practices)). Both clusters share the same 3 nodes and storage, so it adds a single point of failure and a second manual unseal without removing one. |
| **HSM (`pkcs11`) / Seal HA / seal wrapping** | **Not available.** Enterprise-only, and Seal HA explicitly cannot include a Shamir seal ([seal HA](https://developer.hashicorp.com/vault/docs/configuration/seal/seal-ha)). |
| **Static key seal** | **Does not exist in HashiCorp Vault OSS.** Only OpenBao (the fork) has `seal "static"` — a fork trade-off, not a config change. |
| **Shamir + keys in a Kubernetes Secret** (auto-unseal helper) | **Do not do this.** See §3. |

## 3. The one option to refuse explicitly: keys in-cluster

It is trivially implementable (unseal is unauthenticated, so the component
needs only read access to one Secret plus network reach to `:8200`), and it
does give unattended restarts. It also **deletes** the property Shamir
currently provides:

> Anyone with read access to one Secret, plus the Raft data, owns every secret
> Vault holds — with no Vault audit trail.

That "plus the Raft data" bar is lower here than it looks: the nightly
`vault-snapshot-backup` CronJob already reads the entire Raft dataset
(`read`+`sudo` on `sys/storage/raft/snapshot`). The snapshot is age-encrypted
with a key in Vaultwarden, so the pipeline is not trivially exploitable — but
the layering collapses if the Vaultwarden master password and the unseal
shares sit behind the same single human.

Whether that is a severe regression or roughly neutral depends on one fact
only a human can supply: **are the 5 shares genuinely held by different people
with different credentials, or effectively by one?** If it is effectively
"1 of 1" today, the marginal loss is small; if it is genuinely split, this
change is a serious downgrade. Either way it must be a recorded decision, not
a convenience.

## 4. Recommendation

**Primary: keep Shamir. Fix detection and rehearse the procedure.**

1. Alert on sealed/unready Vault pods — added 2026-09-29 in
   `apps/observability/prometheus-values.yaml` (group `vault`), because Vault's
   readiness probe has no `sealedcode=204`, so a sealed pod goes NotReady.
   Scraping Vault's own metrics is **not** an option here: `/v1/sys/metrics`
   returns `permission denied` despite `unauthenticated_metrics_access = true`.
2. Keep the SIGHUP TLS-reload CronJob: it removes the most common reason a
   restart is wanted in the first place.
3. Write and run a **quarterly unseal drill** on a redundant replica, and time
   it. Nobody currently knows how long unsealing takes under pressure.
4. Test a snapshot restore onto a throwaway cluster at least once a quarter.

**Fallback, only if a cloud account already exists: `seal "awskms"`.** Note
that seal migration is not online — it requires briefly taking the whole
cluster down and a fresh verified snapshot first
([seal concepts](https://developer.hashicorp.com/vault/docs/concepts/seal)).

Record the decision *after* the drill. Buying a dependency to solve a problem
of unknown magnitude is the wrong order.

## 5. The fragile thing this evaluation actually surfaced

**The unseal keys live inside the system they are needed to recover.**
Vaultwarden runs in the same cluster as Vault. If the cluster is lost badly
enough to need those keys, retrieving them may require recovering the cluster
first. No auto-unseal option in §2 fixes this — several make it worse by adding
another always-reachable secret.

That is the highest-value follow-up, independent of the seal decision: at
minimum, keep an offline copy of the 5 shares (and the age private key for the
Raft snapshots) somewhere that does not depend on this cluster.

## 6. Open questions for the human

1. Is there **any** cloud account (AWS/GCP/Azure), even unused? Decides whether
   the fallback is live.
2. Are the 5 shares genuinely split across people, or effectively one? (§3)
3. Where is the SealedSecrets private key, and is an offline copy of the unseal
   shares + age key held outside this cluster? (§5)
4. Is a maintenance window available for any seal migration? It cannot be done
   online.
