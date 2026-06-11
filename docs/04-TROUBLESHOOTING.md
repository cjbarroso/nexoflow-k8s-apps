# Troubleshooting & Known Issues

## Application Status

Please be aware of the following application statuses to avoid unnecessary debugging.

### 🪦 Removed applications

WAHA and Cal.com (both broken, never stabilised) were removed from the repo on
2026-06-11. Their manifests live in git history if ever needed; note that the
historical files contain plaintext credentials that must be treated as burned
(see `.gitleaks.toml` and the CI `validate` workflow that now prevents this).

## Common Issues

*   **Argo CD Sync Errors**: If an app fails to sync, check if it relies on a resource in `manifests/` that hasn't been applied or is referenced incorrectly.
*   **Repository Access**: If Argo CD cannot fetch manifests from GitHub, verify `bootstrap/root-app.yaml` points to `https://github.com/cjbarroso/nexoflow-k8s-apps.git` and that the repository remains publicly readable, or configure credentials in `bootstrap/repo-secret.yaml`.
