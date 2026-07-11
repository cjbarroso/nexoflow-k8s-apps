# pami-downloader — scraper on-demand

Job **one-shot** que corre en el cluster a demanda (no es un servicio). Playwright/
Chromium loguea en `efectores.pami.org.ar`, arma un CSV de Órdenes de Pago
(estado GENERADA) y **lo sube a Google Drive**. Código + imagen: repo
`Irupe-Consultores/pami-downloader`.

Namespace propio **`pami`** (producto separado del clínico `hhccia-v2`). Argo CD
sincroniza `src/pami` automáticamente (app `apps/pami/app.yaml`, project `pami`).

## Archivos

| Archivo | Qué es |
|---|---|
| `pami-downloader-cronjob.yaml` | `CronJob` **suspendido** (`suspend: true`). Nunca dispara solo; se lanza a mano. |
| `pami-downloader-netpol.yaml` | Egress: DNS + 443/80 a internet público (rangos privados excluidos). |
| `pami-downloader-secrets.sealedsecret.yaml` | Sólo `PAMI_USER`, `PAMI_PASSWORD` (credenciales). |
| `pami-downloader-gdrive.sealedsecret.yaml` | Key JSON de la Service Account de Google (`sa-key.json`), montada read-only en `/app/sa-key.json`. |

El `GOOGLE_DRIVE_FOLDER_ID` **no es un secreto** → vive como env var plano en
`pami-downloader-cronjob.yaml` (ver "Cambiar carpeta destino").

El pull secret `github-auth` (GHCR) **no vive en Git**; se bootstrapea por-namespace
(igual que en `hhccia-v2`). Ver "Bootstrap".

**Auth de Google Drive = Service Account + Domain-Wide Delegation.** El código
(`listado.spec.ts`) usa `google.auth.GoogleAuth` con
`GOOGLE_APPLICATION_CREDENTIALS=/app/sa-key.json`, scope `drive` y
`supportsAllDrives: true`. Como el destino está en "Mi unidad" (este Workspace
**legacy** no tiene Unidades compartidas) y una SA no tiene cuota propia, la SA
**impersona** al usuario `GOOGLE_IMPERSONATE_USER` (`irupebot@cjbarroso.com`) vía
delegación de dominio. El archivo queda a nombre de ese usuario. Requisitos:
DWD habilitada en la consola de admin (client_id `107507975120778173699`, scope
`https://www.googleapis.com/auth/drive`) y la carpeta destino compartida con
`irupebot@cjbarroso.com` como **Editor**.

## Correr on-demand

```bash
K="kubectl --context nexoflow-cf -n pami"
# lanzar (nombre único por corrida)
$K create job pami-run-$(date +%Y%m%d-%H%M) --from=cronjob/pami-downloader
# seguir logs
$K get jobs -l app=pami-downloader
$K logs -f job/pami-run-YYYYmmdd-HHMM
```

El job termina en `Complete` (exit 0) si logueó en PAMI, generó el CSV y lo subió
a Drive. El CSV queda en la carpeta de Drive (`GOOGLE_DRIVE_FOLDER_ID`); dentro del
pod es efímero (no hay PVC).

## Deploy / actualizar la imagen (SHA-pin)

La imagen se pinnea por **digest inmutable** (`@sha256:...`), `imagePullPolicy:
IfNotPresent`. Al publicar una imagen nueva:

```bash
docker buildx imagetools inspect ghcr.io/irupe-consultores/pami-downloader:latest
# tomar el Digest sha256:... y reemplazarlo en pami-downloader-cronjob.yaml
```

Commit + push a `master` → Argo re-sincroniza el CronJob (~3 min).

## Cambiar carpeta destino

El folder ID es un env var plano. Editá la línea `GOOGLE_DRIVE_FOLDER_ID` en
`pami-downloader-cronjob.yaml`, commit + push a `master`, y el próximo
`create job` usa la carpeta nueva. **Único requisito externo:** compartir la
carpeta nueva con `irupebot@cjbarroso.com` (Editor). No hace falta `kubeseal`,
rebuild, ni tocar la DWD.

## Bootstrap (una sola vez, fuera de Git)

1. **Sellar secrets** (con la app corriendo `kubeseal` contra el controller en
   `kube-system`):

   ```bash
   # credenciales PAMI (el folder id NO va acá: es env plano en el cronjob)
   kubectl create secret generic pami-downloader-secrets -n pami \
     --from-literal=PAMI_USER=... \
     --from-literal=PAMI_PASSWORD=... \
     --dry-run=client -o yaml \
     | kubeseal --controller-namespace kube-system --format yaml \
     > src/pami/pami-downloader-secrets.sealedsecret.yaml

   # key JSON de la Service Account de Google Drive
   kubectl create secret generic pami-downloader-gdrive -n pami \
     --from-file=sa-key.json=./sa-key.json \
     --dry-run=client -o yaml \
     | kubeseal --controller-namespace kube-system --format yaml \
     > src/pami/pami-downloader-gdrive.sealedsecret.yaml
   ```

   ⚠️ Nunca commitear `sa-key.json` en claro; sólo el SealedSecret.

2. **Pull secret GHCR** en el ns `pami` (tras la 1ª sync que crea el namespace):

   ```bash
   K="kubectl --context nexoflow-cf"
   $K get secret github-auth -n hhccia-v2 -o yaml \
     | yq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.ownerReferences)' \
     | $K apply -n pami -f -
   ```

## Rotar credenciales

Regenerar el/los SealedSecret con los pasos de arriba y push a `master`. Para la
Service Account, si se rota la key, generar una key JSON nueva en GCP y re-sellar
`pami-downloader-gdrive`. Para revocar acceso: revocar la DWD en la consola de
admin, deshabilitar la key en GCP, o quitar a `irupebot@cjbarroso.com` de la
carpeta.

## Chromium como root (ya resuelto en la imagen)

La imagen base Playwright corre como `USER root` y Chromium no arranca su sandbox
como root. El fix ya está en el código (`playwright.config.ts`:
`launchOptions.chromiumSandbox: false`), así que no requiere nada en estos
manifests. Si en el futuro se vuelve a ver `Running as root without --no-sandbox
is not supported`, revisar que ese setting siga en el repo `pami-downloader`.
