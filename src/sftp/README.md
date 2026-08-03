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
- The Service is a NodePort (`30222`) so a router can forward public TCP/22 to it.
- Egress is denied. Direct SFTP ingress is limited to TCP/22.

The SFTP endpoint is intentionally direct. Power Automate's managed SFTP-SSH
connector cannot run `cloudflared access ssh` or another client-side proxy.

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

## Publish the endpoint

Configure these outside Kubernetes:

1. Give the selected Kubernetes node a stable LAN address.
2. Forward TCP port `22` on the router to `<node-LAN-IP>:30222`.
3. Create an `A` record for `sftp.cjbarroso.com` pointing to the public IP.
   If the zone is hosted by Cloudflare, leave this record **DNS-only** (gray
   cloud); the standard Cloudflare proxy does not carry SFTP.
4. If possible, allowlist the Power Automate managed connector IP ranges at the
   router/firewall. Microsoft publishes the region-specific ranges at
   <https://learn.microsoft.com/en-us/connectors/common/outbound-ip-addresses>.

Do not run `cloudflared tunnel route dns` for this hostname. If opening an
inbound router port is unacceptable, the alternative is a paid Cloudflare
Spectrum TCP application or another public TCP relay; that configuration is
outside this repository.

## Power Automate connection

Create a connection using the **SFTP-SSH** connector with:

- Host server address: `sftp.cjbarroso.com`
- Port: `22`
- User name: `sftp`
- Password: the password used in `SFTP_USERS`
- Root folder path: `/upload`

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
