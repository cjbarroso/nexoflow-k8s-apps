# HTTPS file upload

Single-user HTTPS file drop for `upload.cjbarroso.com`.

## Design

- Server: a small Python standard-library HTTP service, packaged in a pinned
  `python:3.13.7-alpine3.22` image.
- One replica and a `Recreate` strategy because the upload volume is RWO.
- One 1 GiB Longhorn PVC mounted at `/data`; uploaded files are stored in its
  `/upload` directory.
- Each request is authenticated with a bearer token and accepts one raw file
  body up to 1 MiB.
- Uploads use a temporary file, `fsync`, and an atomic hard link. Existing files
  are never overwritten.
- The pod runs as UID/GID 1000 with a read-only root filesystem and no service
  account token.
- Egress is denied. Only the Cloudflare tunnel namespace may reach port 8080.

## Credentials

The application expects a SealedSecret-generated Secret named
`sftp-credentials` with one key, `UPLOAD_TOKEN`. The generated
`sftp-credentials-sealedsecret.yaml` is safe to commit; the repository also
contains the excluded plaintext template `sftp-credentials.example.yaml`.

Create and seal it with a strong random token. This PowerShell 5.1-compatible
example generates 32 random bytes:

```powershell
$tmp = Join-Path $env:TEMP 'sftp-credentials.yaml'
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$bytes = New-Object byte[] 32
$rng.GetBytes($bytes)
$rng.Dispose()
$token = [Convert]::ToBase64String($bytes)
kubectl create secret generic sftp-credentials `
  --namespace sftp `
  --from-literal="UPLOAD_TOKEN=$token" `
  --dry-run=client -o yaml | Out-File -Encoding utf8 $tmp
kubeseal --controller-name sealed-secrets-controller `
  --controller-namespace kube-system -f $tmp -o yaml `
  | Out-File -Encoding utf8 src\sftp\sftp-credentials-sealedsecret.yaml
Remove-Item $tmp
```

Keep the token in the Power Automate connection or a password manager. The
generated file is managed by Argo; do not commit the plaintext Secret or the
temporary file.

## Cloudflare setup

The `ingress.yaml` file uses the existing Cloudflare Tunnel Ingress Controller.
It automatically creates the `upload.cjbarroso.com` DNS record and routes HTTPS
traffic to the Service. No router port-forward or manual DNS record is needed.

After Argo syncs the app, check:

```bash
kubectl -n sftp get ingress sftp
kubectl -n sftp get svc,pods,pvc
```

## Power Automate connection

Use a Power Automate HTTP action or custom connector that permits custom
headers. Configure:

- Method: `POST`
- URI: `https://upload.cjbarroso.com/upload`
- Header `Authorization`: `Bearer <UPLOAD_TOKEN>`
- Header `X-Filename`: the source file's original filename
- Body: the source file's binary content, not a base64-encoded string

The service returns `201 Created` with the stored filename and byte count. It
returns `401` for an invalid token, `409` when the filename already exists, and
`413` for files larger than 1 MiB.

Uploaded files are stored in the `upload` directory of the PVC and are not
available for browsing or deletion through the HTTP endpoint.

## Verification

```bash
kubectl -n sftp get pods,pvc,svc,ingress
kubectl -n sftp logs deploy/sftp
curl https://upload.cjbarroso.com/healthz
curl -X POST https://upload.cjbarroso.com/upload `
  -H "Authorization: Bearer <UPLOAD_TOKEN>" `
  -H "X-Filename: example.txt" `
  --data-binary "@example.txt"
```
