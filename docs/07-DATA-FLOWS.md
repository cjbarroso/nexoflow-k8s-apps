# Data Flows, Retention & Compliance Map

Snapshot date: 2026-06-11. This is the foundation document for the medical
compliance workstream: where clinical data (PHI) lives, how it moves, what
third parties touch it, and the open decisions that need legal/operator input.
Update it whenever a component or data path changes.

## 1. Clinical data path (PHI)

```
Datatech MSSQL (SRN, 192.168.5.132 — live clinical production DB, external)
        │  poll (watermark window, batches of DISCOVERY_LIMIT)
        ▼
hhccia-adapter-datatech (ns hhccia-v2)          ← egress-locked: DNS+NATS+MSSQL only
        │  publish hhccia.records.* events
        ▼
NATS JetStream (PVC-backed stream HHCCIA)        ← event payloads CONTAIN clinical text
        │  durable consumers (core-*)
        ▼
hhccia-core (FastAPI)
        │  ├── store → CNPG Postgres hhccia-core-db (PVC + R2 backups)
        │  ├── AI analysis → Google Gemini API (gemini-3.5-flash, flash-lite)   ⚠ PHI leaves the cluster
        │  └── write-back of approved edits → adapter → MSSQL
        ▼
hhccia-front (Angular SPA) ← browser ← Cloudflare tunnel (medaudit.irupeconsultores.com)
```

Auth on every human entry point: Authentik OIDC (`auth.irupeconsultores.com`).

## 2. Where PHI is at rest

| Store | Location | Encryption at rest | Retention | Notes |
|---|---|---|---|---|
| Datatech MSSQL (source) | 192.168.5.132 (LAN, external system) | Datatech's responsibility | Datatech's policy | System of record |
| CNPG `hhccia-core-db` | local-path PVC on homestation | ❌ none (plain node disk) | indefinite (app data) | primary + standby |
| NATS JetStream PVC | local-path PVC | ❌ none | stream retention (app-configured) | event payloads = clinical text |
| R2 `velero-backups/cnpg/*` | Cloudflare R2 | ✅ Cloudflare-managed | 30 d | WAL + base backups of both DBs |
| R2 `velero-backups/velero/` | Cloudflare R2 | ✅ Cloudflare-managed | 30 d | authentik + vaultwarden FS backups (no clinical PHI) |
| Loki | local-path PVC | ❌ none | 30 d | HCL/PAC identifiers **masked at collection** since 2026-06-11 (Alloy stage.replace); logs before that date may contain identifiers until they age out ≤2026-07-11 |
| Prometheus | local-path PVC | ❌ none | 15 d | metrics only, no PHI |

## 3. Third parties that touch data

| Party | What they see | Contract needed |
|---|---|---|
| **Google (Gemini API)** | Clinical record text sent for analysis + voice-edit | ⚠ **OPEN: DPA / data-processing terms, data-residency, training-opt-out.** Highest-priority legal item. Mitigation option: pseudonymize (strip HCL/PAC/names) before the API call — needs app change. |
| **Cloudflare** | TLS terminates at the Cloudflare edge → tunnel; CF can technically see request bodies (incl. PHI in API responses to the browser) | ⚠ OPEN: DPA with Cloudflare (they offer one self-serve). |
| **Cloudflare R2** | Encrypted backups (DB dumps = PHI) | covered by same CF DPA |
| **healthchecks.io** | heartbeat pings only — no PHI | none |
| **Telegram (alerts)** | alert names/descriptions — no PHI by construction (keep it that way when adding alerts) | none |
| **GitHub** | manifests, sealed secrets — no PHI; repo is public | none |

## 4. Data in transit

- Browser ↔ Cloudflare: TLS. Cloudflare ↔ cluster: tunnel (TLS).
- **In-cluster traffic is plaintext** (no mesh/mTLS): adapter→NATS, core→Postgres, core→authentik. Acceptable on a single physical node; revisit when multi-node (traffic crosses a real network).
- adapter ↔ MSSQL: TDS over the LAN — ⚠ OPEN: confirm whether the connection is TLS-encrypted (driver setting) or plaintext on the LAN.

## 5. Access control

- Humans: Authentik OIDC in front of the app, Grafana, Argo CD. User inventory lives in Authentik (CNPG-backed, PITR).
- Cluster: single kubeconfig (admin) — ⚠ OPEN: no per-person identity on kubectl access, no K8s API audit logging (k3s supports it via apiserver args; needs node access + restart).
- Network: default-deny ingress in the four app namespaces; adapter egress-locked (see §1).

## 6. Open items (decision/owner needed)

1. **Gemini DPA + pseudonymization** — legal review + app change. The single biggest compliance exposure.
2. **Which regulation applies** (HIPAA-equivalent? Argentina Ley 26.529/25.326? EU GDPR?) — drives retention numbers and breach-notification duties. Everything below depends on this.
3. **Retention**: Postgres is indefinite; logs/backups 15–30 d. Medical audit-trail requirements are typically *years* — likely need: longer DB backup retention + Loki→R2 archival for audit logs.
4. **Node disk encryption** (LUKS) — PHI sits unencrypted on the homestation disk today; also k3s secrets-encryption at rest. Host-level work on existing hardware.
5. **K8s API audit logging** — host-level k3s flag.
6. **MSSQL connection encryption** — verify TDS TLS.
7. **Per-person cluster access** — OIDC kubectl (Authentik can be the IdP) instead of one shared kubeconfig.
