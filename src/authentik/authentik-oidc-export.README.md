# Authentik OIDC config export (`authentik-oidc-export.json`)

A **sanitized, point-in-time export** of Authentik's OIDC **providers** and
**applications** — the SSO config that is otherwise only in the Authentik
Postgres DB and is configured **by hand** (the in-repo `blueprints.yaml` is not
applied; see the `project_authentik_config_manual` note). This file makes that
config **documented and reproducible**, so it isn't a single copy in the DB.

## What's captured
- **Providers** (`authentik_providers_oauth2.oauth2provider`): `client_id`,
  `client_type`, **`_redirect_uris`** (the critical bit), token validities,
  `sub_mode`, `signing_key` (a UUID reference, not key material), etc.
- **Applications** (`authentik_core.application`): name, slug, launch URL.

Current contents (2026-05-30): provider `hhccia-front` (public/PKCE — front v2,
redirect URIs for `hhccia-v2.cjbarroso.com`, `medaudit.irupeconsultores.com`,
`localhost:4200`) and the Grafana provider (confidential, redirect
`logs.cjbarroso.com/login/generic_oauth`); apps `HHCCIA` and `Grafana`.

## Secrets
`client_secret` is **REDACTED** — it is not stored in Git. The real values live in:
- the **Velero backup of the Authentik DB** (ns `authentik`, daily `stateful-daily` schedule), and
- for Grafana, the sealed secret `grafana-secrets` (`oidc-client-secret`).
`hhccia-front` is a **public** client (PKCE) — it has no usable client secret.

## How to regenerate this export
`ak export_blueprint` is currently broken in this Authentik version
(`KeyError: 'serializer'`), so use Django `dumpdata`:
```powershell
$env:KUBECONFIG = "C:\Users\Usuario\.kube\nexoflow.config"
kubectl -n authentik exec deploy/authentik-server -- `
  ak dumpdata authentik_providers_oauth2.OAuth2Provider authentik_core.Application --indent 2 > export.json
# then redact `client_secret` before committing
```

## Using it in disaster recovery
Preferred path: restore the Authentik DB from the Velero backup (config + secrets
come back intact). If instead Authentik is rebuilt fresh, recreate these
providers/apps (by hand from this file, or `ak loaddata` then fix secrets):
set the **redirect URIs exactly as listed**, regenerate `client_secret`, and
update the consumer — Grafana → reseal `grafana-secrets`; `hhccia-front` needs
none (public/PKCE). See `Reference/Disaster Preparedness - full backup coverage plan.md`
in the HHCCIA hub.

> This is a **point-in-time snapshot** — re-run the export after changing OIDC config.
