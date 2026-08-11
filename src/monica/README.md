# Monica

Monica is deployed from the official `monica:4.1.2` Apache image with a
single-replica MariaDB StatefulSet. The web application and scheduler share
the Longhorn-backed `/var/www/html/storage` volume. MariaDB logical dumps run
at 01:30 UTC so the 02:00 Velero backup captures a consistent database copy.

Web access is through the Cloudflare Tunnel at
`https://monica.irupeconsultores.com`; the database is cluster-internal only.

## Secrets

`monica-secrets.example.yaml` is excluded from Argo. Create the real values and
seal them with the in-cluster controller before syncing the `monica` app. The
secret must contain `APP_KEY`, `HASH_SALT`, `DB_DATABASE`, `DB_USERNAME`,
`DB_PASSWORD`, and `MARIADB_ROOT_PASSWORD`.

Signups are initially enabled so the first account can be created. Change
`APP_DISABLE_SIGNUP` to `"true"` in `configmap.yaml` after bootstrap.
