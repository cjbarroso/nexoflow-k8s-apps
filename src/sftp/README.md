# sftp

Single-user SFTP file drop for `sftp.cjbarroso.com`.

## Design

- Server: `atmoz/sftp:alpine`, pinned to an immutable image digest.
- One replica and a `Recreate` strategy because the upload volume is RWO.
- One 1 GiB Longhorn PVC mounted as the user's chroot home.
- The only writable directory is `/upload` inside the SFTP chroot.
- SSH host keys are retained on the PVC so pod recreation does not change the
  server fingerprint.
- The pod runs as root because the image entrypoint must create the account and
  start OpenSSH; its SFTP configuration disables shell access and TCP forwarding.
- The Service is `ClusterIP`; the Cloudflare tunnel controller reaches it on SSH
  port 22.
- Egress is denied. Tunnel SFTP ingress is limited to TCP/22.

The existing `cloudflare-tunnel` IngressClass manages the Cloudflare tunnel route
and DNS record for `sftp.cjbarroso.com`.

## Credentials

The application expects a SealedSecret-generated Secret named
`sftp-credentials` with one key, `SFTP_USERS`. The generated
`sftp-credentials-sealedsecret.yaml` is safe to commit; the repository also
contains the excluded plaintext template `sftp-credentials.example.yaml`.

Create and seal it with a strong password (do not use `:` or whitespace in the
password because those characters delimit the atmoz user specification):

```powershell
$tmp = Join-Path $env:TEMP 'sftp-credentials.yaml'
kubectl create secret generic sftp-credentials `
  --namespace sftp `
  --from-literal='SFTP_USERS=sftp:REPLACE_WITH_LONG_RANDOM_PASSWORD:1000:1000:upload' `
  --dry-run=client -o yaml | Out-File -Encoding utf8 $tmp
kubeseal --controller-name sealed-secrets-controller `
  --controller-namespace kube-system -f $tmp -o yaml `
  | Out-File -Encoding utf8 src\sftp\sftp-credentials-sealedsecret.yaml
Remove-Item $tmp
```

Replace the placeholder before running the command. The generated file is
managed by Argo; do not commit the plaintext Secret or the temporary file.

## Cloudflare setup

`ingress.yaml` uses the existing Cloudflare Tunnel Ingress Controller with
`backend-protocol: ssh`. It automatically creates the DNS record and routes the
hostname to the SFTP Service. No router port-forward or manual DNS record is
needed.

After Argo syncs the app, check:

```bash
kubectl -n sftp get ingress sftp
kubectl -n sftp describe ingress sftp
```

## Power Automate connection

Create a connection using the **SFTP-SSH** connector with:

- Host server address: `sftp.cjbarroso.com`
- Port: `22`
- User name: `sftp`
- Password: the password used in `SFTP_USERS`
- Root folder path: `/upload`

Important: the controller's documented SSH flow uses
`cloudflared access ssh` on the client when the hostname is protected by
Cloudflare Access. Power Automate cannot run that client-side proxy. If the
managed connector cannot establish a native SSH session to this hostname, use
Cloudflare Spectrum or the direct NodePort/router design instead.

Power Automate supports SSH host-key validation. Prefer supplying the RSA MD5
fingerprint instead of disabling validation:

```bash
kubectl -n sftp exec deploy/sftp -- \
  ssh-keygen -l -E md5 -f /etc/ssh/ssh_host_rsa_key.pub
```

Copy the reported MD5 fingerprint into the connector's **SSH host key
finger-print** field. The connector also supports RSA private-key
authentication if you later choose to replace password authentication.

Uploaded files are stored in the `upload` directory of the PVC.

## Verification

```bash
kubectl -n sftp get pods,pvc,svc
kubectl -n sftp logs deploy/sftp
kubectl -n sftp get svc sftp -o wide
```
