# hhccia-prestaciones-export (weekly OH/ON prestaciones CSV)

Read-only weekly export of OH/ON prestaciones (códigos 145001/145005) + ingreso
data, with a locally-classified `RUTA_ADMIN` column, from Datatech MSSQL to an
**on-prem PVC** (PII never leaves the facility). Code/image:
repo `hhccia-prestaciones-export`. Design/spec: vault
`🚀SPACES/HHCCIA/Wayfinder/prestaciones-oh-on/`.

## Files
- `hhccia-prestaciones-export-pvc.yaml` — Longhorn RWO volume for the CSVs.
- `hhccia-prestaciones-export-cronjob.yaml` — weekly run (Mon 07:00 GMT-3 via `timeZone`).
- `hhccia-prestaciones-export-netpol.yaml` — egress lockdown: DNS + MSSQL only (no internet).
- `hhccia-prestaciones-export-fetch.yaml` — helper pod to `kubectl cp` the CSVs.
- `hhccia-prestaciones-export-db-sealedsecret.yaml` — read-only `n8n` login (least privilege).

All pinned to node `homestation` (LAN route to MSSQL + shared RWO PVC).

## Deploy (prod = manual SHA bump, like the other hhccia-v2 workloads)
1. Push repo `hhccia-prestaciones-export` to GitHub `main` → GH Actions builds
   `ghcr.io/irupe-consultores/hhccia-prestaciones-export:latest` + `:<sha>`.
2. In the CronJob, replace `:latest` with the built **git SHA** (`imagePullPolicy: IfNotPresent`).
3. Merge this branch to `master`, push → Argo CD auto-syncs the namespace.
4. Verify (below).

## Verify / smoke
```bash
K="kubectl --context nexoflow-cf -n hhccia-v2"
# one-off run of the weekly job now
$K create job pex-smoke --from=cronjob/hhccia-prestaciones-export-weekly
$K logs -f job/pex-smoke                      # expect "export ok: N rows ... RUTA_ADMIN distribution: ..."
# retrieve the CSV from the fetch helper
POD=$($K get pod -l app=hhccia-prestaciones-export,role=fetch -o name | head -1)
$K cp "${POD#pod/}:/out" ./out-local
```

## Ad-hoc run with an explicit date range
```bash
$K create job pex-jun --from=cronjob/hhccia-prestaciones-export-weekly --dry-run=client -o yaml \
  | yq '.spec.template.spec.containers[0].env += [{"name":"DATE_FROM","value":"2026-06-01"},{"name":"DATE_TO","value":"2026-07-01"}]' \
  | $K apply -f -
# (or: create the job, then edit env before pods start; DATE_FROM inclusive, DATE_TO exclusive)
```

## Notes
- The read-only sealed secret must exist before the job can start (applied with
  the rest via Argo). Rotate command is in the sealed-secret file header.
- CSV filter/joins are the verified query (see the vault SQL). Date column is
  `CLIORD.FEC`.
