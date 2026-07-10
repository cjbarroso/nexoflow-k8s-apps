# hhccia-prestaciones-export

Read-only weekly export of OH/ON prestaciones plus ingreso data. `RUTA_ADMIN`
is classified in bulk by Gemini 3.1 Flash-Lite. Only deduplicated `CLIPAC_OBS`
strings leave the facility; the complete CSV remains on the on-prem PVC.

Code/image: `hhccia-prestaciones-export`. Design/spec: HHCCIA vault
`Wayfinder/prestaciones-oh-on/`.

## Resources

- `hhccia-prestaciones-export-pvc.yaml`: Longhorn RWO volume for CSV files.
- `hhccia-prestaciones-export-cronjob.yaml`: Monday 07:00 Argentina time.
- `hhccia-prestaciones-export-netpol.yaml`: DNS, MSSQL, and public HTTPS only.
- `hhccia-prestaciones-export-fetch.yaml`: read-only `kubectl cp` helper.
- `hhccia-prestaciones-export-db-sealedsecret.yaml`: read-only Datatech login.
- `hhccia-core-secrets`: existing sealed `GEMINI_API_KEY`, referenced by key.

All workloads mount the RWO volume on `homestation`.

## Deploy

1. Push `hhccia-prestaciones-export` main so GitHub Actions publishes the SHA tag.
2. Pin that full git SHA in `hhccia-prestaciones-export-cronjob.yaml`.
3. Push `nexoflow-k8s-apps` master; Argo CD auto-syncs `hhccia-v2`.
4. Run the smoke test below.

## Smoke test

```powershell
$Context = 'nexoflow-cf'
$Namespace = 'hhccia-v2'
$Job = 'pex-smoke-' + (Get-Date -Format 'yyyyMMddHHmmss')

kubectl --context $Context -n $Namespace create job $Job `
  --from=cronjob/hhccia-prestaciones-export-weekly
kubectl --context $Context -n $Namespace wait --for=condition=complete `
  "job/$Job" --timeout=15m
kubectl --context $Context -n $Namespace logs "job/$Job"

$Pod = kubectl --context $Context -n $Namespace get pod `
  -l 'app=hhccia-prestaciones-export,role=fetch' `
  -o jsonpath='{.items[0].metadata.name}'
kubectl --context $Context -n $Namespace cp "${Pod}:/out" './out-local'
```

Expected logs include `export ok` and a `RUTA_ADMIN distribution`.

## Ad-hoc date range

Create a job from the CronJob, then patch its environment before creation with
the preferred Kubernetes YAML tooling. `DATE_FROM` is inclusive and `DATE_TO`
is exclusive. Do not edit the live weekly CronJob for a one-off export.

## Security notes

- The Gemini request contains only `{id, text}` pairs derived from `CLIPAC_OBS`.
- No fallback to local rules is used. Invalid or incomplete model output fails
  the job, which makes the failure visible and lets the CronJob retry.
- Kubernetes `NetworkPolicy` cannot restrict by FQDN. Public TCP/443 is allowed
  for the exporter, with private/link-local IPv4 ranges excluded. Datatech MSSQL
  is the only explicit private-network exception.
- The fetch helper is excluded from the exporter policy by its `role=fetch`
  label and has no egress allowance.
