# Authentik OIDC config export (`authentik-oidc-export.json`)

A **sanitized, point-in-time export** of Authentik's OIDC **providers** and
**applications** — the SSO config that otherwise lives only in the Authentik
Postgres DB. The in-repo `blueprints.yaml` **is applied** (mounted whole-dir at
`/blueprints/custom`; provider redirect_uris + brand are declarative — see the
corrected `project_authentik_config_manual` note, 2026-05-31), so it is the
source of truth for the fields it manages. This export still serves as a
documented, reproducible snapshot of the full live config (including fields the
blueprint doesn't set), so it isn't a single copy in the DB.

## What's captured
- **Providers** (`authentik_providers_oauth2.oauth2provider`): `client_id`,
  `client_type`, **`_redirect_uris`** (the critical bit), token validities,
  `sub_mode`, `signing_key` (a UUID reference, not key material), etc.
- **Applications** (`authentik_core.application`): name, slug, launch URL.

Current contents (2026-05-31, post domain migration): provider `hhccia-front`
(public/PKCE — front v2, redirect URIs for `medaudit.irupeconsultores.com` and
`localhost:4200`; the legacy `hhccia-v2.cjbarroso.com` callback was removed) and
the Grafana provider (confidential, redirect `logs.cjbarroso.com/login/generic_oauth`
— still on cjbarroso, intentionally not migrated); apps `HHCCIA`
(launch `https://medaudit.irupeconsultores.com/`) and `Grafana`.

## Secrets
`client_secret` is **REDACTED** — it is not stored in Git. The real values live in:
- the **Velero backup of the Authentik DB** (ns `authentik`, daily `stateful-daily` schedule), and
- for Grafana, the sealed secret `grafana-secrets` (`oidc-client-secret`).
`hhccia-front` is a **public** client (PKCE) — it has no usable client secret.

## How to regenerate this export
`ak export_blueprint` was broken on the old `2024.10` image
(`KeyError: 'serializer'`); it works again as of the `2026.5.2` upgrade
(2026-06-03). The `dumpdata` recipe below still works and produces this exact
shape, so it's kept as the canonical method:
```powershell
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
