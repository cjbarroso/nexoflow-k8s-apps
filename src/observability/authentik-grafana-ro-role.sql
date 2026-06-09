-- Read-only Grafana login for the Authentik identity DB.
--
-- Applied BY HAND on the Authentik Postgres (the plain `authentik-pg` Deployment,
-- ns `authentik`) — Authentik owns its own schema migrations, so we deliberately
-- do NOT manage this via them and do NOT create a dependent VIEW (a view would
-- risk blocking a future Authentik column migration). Recreate this if that DB is
-- ever rebuilt. The password MUST match the `db-password` key of the
-- `authentik-grafana-ro` SealedSecret in ns `observability`
-- (authentik-grafana-ro-sealedsecret.yaml), which is what Grafana injects as
-- $__env{AUTHENTIK_DB_PASSWORD}.
--
-- Column-level SELECT on authentik_core_user deliberately EXCLUDES `password`
-- (the password hash) so this login can never read credential material. Full
-- SELECT on authentik_events_event for the login-events panels.
--
-- Apply (password read from the DPAPI cred file, never typed/echoed):
--   $P  = (Import-Clixml "$env:USERPROFILE\.hhccia\authentik-grafana-ro.cred.xml").GetNetworkCredential().Password
--   $pod = (kubectl --context nexoflow-cf -n authentik get pods -l app=authentik-pg -o jsonpath='{.items[0].metadata.name}')
--   Get-Content "<this file>" | kubectl --context nexoflow-cf -n authentik exec -i $pod -- psql -U authentik -d authentik -v pw="$P" -f -

\set ON_ERROR_STOP on

-- Idempotent role create (no password here — set below so the var works outside
-- any dollar-quoted block, where psql does not substitute :vars).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_ro') THEN
    CREATE ROLE grafana_ro LOGIN;
  END IF;
END
$$;

ALTER ROLE grafana_ro WITH LOGIN PASSWORD :'pw';

GRANT CONNECT ON DATABASE authentik TO grafana_ro;
GRANT USAGE ON SCHEMA public TO grafana_ro;

GRANT SELECT (id, uuid, username, name, email, is_active, date_joined, last_login, type, path, attributes)
  ON authentik_core_user TO grafana_ro;

GRANT SELECT ON authentik_events_event TO grafana_ro;

-- Quick verification (should list the two tables with the granted privileges):
--   \dp authentik_core_user
--   \dp authentik_events_event
