# Machine user (M2M) — the `svc-hhccia` service account & app password

How a **non-human** ("machine") client authenticates to services fronted by this
Authentik, using the `svc-hhccia` service account and an OAuth2
`client_credentials` **app password**. This is the machine-only path that exists
*alongside* the Google-SSO-only browser login (it does not weaken it).

## What is provisioned

| Piece | Value / where | Managed in |
|---|---|---|
| Service account | `svc-hhccia` (`type: service_account`; cannot do the Google browser login) | Git — `blueprints.yaml` → `machine-user.yaml` |
| Grant on the `hhccia` provider | `client_credentials` added to `client_id: hhccia-front` as a **superset** (`authorization_code` + `refresh_token` + `client_credentials`), so the SPA keeps working | Git — `blueprints.yaml` → `hhccia.yaml` |
| App-access gate | `svc-hhccia` is a member of `hhccia-users` (the HHCCIA app policy binding) — required or the token request is denied | Runtime (added via `ak`; membership is UI/DB data, not Git) |
| `service` claim | `["IN", "in", "TI"]` (all in-scope services); **no** admin flags → physician-level access scoped to those services | Git — `machine-user.yaml` `attributes.service` |
| **App password** (the secret) | a `Token` row with `intent: app_password` on `svc-hhccia` | **Runtime secret — NOT in Git** (create/seal it, below) |

## The core flow: app password → JWT

The machine **never** sends the app password to the target service. It trades it
to Authentik for a short-lived JWT, then presents the JWT:

```
┌─────────┐ 1. grant_type=client_credentials            ┌──────────────────────┐
│ machine │    client_id=hhccia-front                   │ authentik            │
│ client  │    username=svc-hhccia                      │ POST /application/o/ │
│         │    password=<APP_PASSWORD>      ──────────▶ │      token/          │
│         │ ◀──────────  access_token (JWT, ~1h)  ───── │   (global endpoint)  │
│         │                                             └──────────────────────┘
│         │ 2. Authorization: Bearer <JWT>              ┌──────────────────────┐
│         │ ──────────────────────────────────────────▶ │ target service       │
│         │ ◀────────────────────────────────────────── │ (validates the JWT)  │
└─────────┘                                             └──────────────────────┘
```

```bash
# 1. Exchange the long-lived app password for a short-lived JWT.
#    NOTE: the token endpoint is GLOBAL (/application/o/token/); client_id
#    selects the provider. It is NOT /application/o/hhccia/token/ (that 405s).
TOKEN=$(curl -s https://auth.irupeconsultores.com/application/o/token/ \
  -d grant_type=client_credentials \
  -d client_id=hhccia-front \
  -d username=svc-hhccia \
  -d password="$APP_PASSWORD" \
  -d scope=profile | jq -r .access_token)

# 2. Call the service with the JWT.
curl -H "Authorization: Bearer $TOKEN" https://<service>/api/...
```

The JWT carries `iss = https://auth.irupeconsultores.com/application/o/hhccia/`
(what the core validates), `service = ["IN","in","TI"]`, and the admin flags all
`false`. Access-token lifetime is `hours=1` (`access_token_validity` on the
provider) — re-mint on expiry; don't cache the JWT long-term.

## Where the app password / JWT works — and where it does NOT

An Authentik JWT is only useful against a **resource server** — an app that
validates `Authorization: Bearer <JWT>` on its API. Apps that are OIDC *relying
parties* (browser session login) do **not** accept the JWT as API auth; each
needs its **own native machine credential**.

| Target | What it is | Use the Authentik app password / JWT? |
|---|---|---|
| **HHCCIA core** | Resource server (the medaudit SPA calls it with the JWT; validates `iss` + JWKS) | ✅ Yes — bearer JWT |
| **Hermes** (`hermes.cjbarroso.com`) | Fronted by the Authentik proxy outpost | ✅ Bearer JWT / static SA token through the outpost |
| **Grafana** (`logs.cjbarroso.com`) | OIDC RP (`auth.generic_oauth`, browser session) | ❌ Use a **Grafana service-account token** |
| **Planka** (`planka.irupeconsultores.com`) | OIDC RP (browser session) | ❌ Use a Planka API token |
| **Prestaciones export UI** | OIDC RP (Authlib session) | ❌ Use its own machine credential |

## Example A — HHCCIA core (works with the JWT)

The core is the one app that validates the bearer JWT (the SPA already does
exactly this). Use the flow above; point step 2 at the core's API base URL (the
same origin the medaudit SPA calls). The JWT's `service` claim scopes which
records the machine can see (`IN`/`in`/`TI`); with no admin flag it gets
physician-level access.

## Example B — Grafana (use a Grafana service-account token, NOT the app password)

Grafana authenticates *users* through the browser OIDC flow
(`auth.generic_oauth` → Authentik) and keeps a **session**; its HTTP API does
**not** validate the Authentik JWT as a bearer token. So the `svc-hhccia` app
password cannot drive Grafana. The correct M2M credential is a **Grafana
service-account token** (Grafana 9+; replaces legacy API keys).

Create one (UI): **Administration → Users and access → Service accounts → Add
service account** (pick a role: `Viewer`/`Editor`/`Admin`) → **Add token** →
copy the `glsa_…` value (shown once).

Or via the API, using the local Grafana admin (basic auth still works —
`disable_login_form: false`; creds in the sealed secret `grafana-secrets`):

```bash
# create the service account (returns an id)
curl -s -X POST https://logs.cjbarroso.com/api/serviceaccounts \
  -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  -H 'Content-Type: application/json' \
  -d '{"name":"machine-ro","role":"Viewer","isDisabled":false}'

# create a token for it (use the id from above); the .key is the token (shown once)
curl -s -X POST https://logs.cjbarroso.com/api/serviceaccounts/<ID>/tokens \
  -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  -H 'Content-Type: application/json' \
  -d '{"name":"machine-ro-token"}' | jq -r .key
```

Use it (this *is* a bearer token Grafana's API accepts):

```bash
curl -H "Authorization: Bearer glsa_..." \
  https://logs.cjbarroso.com/api/dashboards/uid/<dashboard-uid>
```

> The Grafana role of a service-account token is set on the service account
> itself; it is **independent** of the Authentik `groups → role` mapping
> (`role_attribute_path`), which only applies to interactive SSO logins.

## Creating / rotating the app password (via `ak`)

There is no separate "Service Accounts" menu in this build — the account shows
under **Directory → Users** (type `service_account`). The app password is a
`Token` (`intent: app_password`); create it with `ak` so the secret is generated
and seen only in your terminal. Run this (PowerShell, `nexoflow-cf` context;
keep the closing `'@` at column 0):

```powershell
$py = @'
from authentik.core.models import Token, User
from django.test import Client
import secrets
u = User.objects.get(username="svc-hhccia")
key = secrets.token_urlsafe(64)
t = Token.objects.create(
    identifier="svc-hhccia-m2m",
    intent="app_password",
    user=u,
    expiring=False,
    key=key,
    description="M2M client_credentials app password for svc-hhccia",
)
print("APP_PASSWORD=" + t.key)
c = Client()
resp = c.post("/application/o/token/", data={
    "grant_type": "client_credentials",
    "client_id": "hhccia-front",
    "username": "svc-hhccia",
    "password": t.key,
    "scope": "profile",
}, HTTP_HOST="auth.irupeconsultores.com")
print("VERIFY status=" + str(resp.status_code) + " ok=" + str("access_token" in resp.content.decode()))
'@
$py | kubectl -n authentik exec -i deploy/authentik-server -- ak shell 2>&1 | Select-String -Pattern 'APP_PASSWORD|VERIFY'
```

- `APP_PASSWORD=<secret>` — the app password; seal it for the consumer (mirror
  `src/observability/README.md`). Non-expiring (`expiring=False`).
- `VERIFY status=200 ok=True` — confirms it already mints a valid JWT.

**Rotate**: create a new token with a fresh identifier (e.g. `svc-hhccia-m2m-2`),
update the consumer's sealed secret, then delete the old token
(`Token.objects.filter(identifier="svc-hhccia-m2m").delete()`).

## Security notes

- The **app password is long-lived** — treat it like a password. Seal it
  (SealedSecret); never commit it in plaintext.
- The **JWT is short-lived** (`hours=1`); re-mint as needed, don't store it.
- `svc-hhccia` can do whatever its groups/attributes allow (physician-level on
  `IN`/`in`/`TI`, no admin). Keep that surface minimal; change scope via
  `attributes.service` (Git) and group membership (UI/`ak`).
- A failed `client_credentials` attempt logs a `login_failed` event for
  `svc-hhccia` (auth method `token`) — useful for auditing machine usage.
