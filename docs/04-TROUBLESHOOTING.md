# Troubleshooting & Known Issues

## Application Status

Please be aware of the following application statuses to avoid unnecessary debugging.

### 🔴 Do Not Deploy / Broken

The following applications are currently **Work In Progress (WIP)** or have known blocking errors. **Do not attempt to deploy or fix them without checking with the lead developer.**

1.  **WAHA (WhatsApp HTTP API)**:
    *   **Location**: `apps/waha/`
    *   **Status**: Commented out / Broken.
    *   **Reason**: Deployment issues / Configuration incomplete.

2.  **Cal.com**:
    *   **Location**: `manifests/cal.com/` (Note: No corresponding `apps/` entry verified).
    *   **Status**: Broken.
    *   **Reason**: Deployment issues.

## Common Issues

*   **Argo CD Sync Errors**: If an app fails to sync, check if it relies on a resource in `manifests/` that hasn't been applied or is referenced incorrectly.
*   **Repository Access**: If Argo CD cannot fetch manifests from GitHub, verify `bootstrap/root-app.yaml` points to `https://github.com/cjbarroso/nexoflow-k8s-apps.git` and that the repository remains publicly readable, or configure credentials in `bootstrap/repo-secret.yaml`.
