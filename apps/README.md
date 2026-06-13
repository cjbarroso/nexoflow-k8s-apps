# apps

Argo CD Application definitions for the cluster. Each subdirectory contains
an `app.yaml` (or equivalent) that points to a Helm chart or a path under
`../src/` for plain YAML manifests.

Bootstrap entry point: `../bootstrap/root-app.yaml` (app-of-apps pattern).

See `../docs/02-ARCHITECTURE.md` and `../docs/06-APP-STRUCTURE.md`.
