# Cal.com Deployment with Dynamic Database Credentials

This directory contains the ArgoCD Application definition for Cal.com. The actual Kubernetes manifests are located in `manifests/cal.com` (GitOps pattern with multiple sources).

## Architecture & Database Authentication

We use the official [pyrrha/calcom-helm](https://github.com/pyrrha/calcom-helm) chart. However, this chart has a known limitation: it hardcodes the retrieval of mandatory environment variables (like `DATABASE_URL`) from a single secret specified in `values.yaml` (`calcom-runtime-secrets` in our case). It does **not** support overriding these variables via `extraEnv` or `env` lists in `values.yaml`.

Since we use **CloudNativePG (CNPG)** for the database, credentials are dynamically generated and rotated in the `calcom-cluster-app` secret. This creates a conflict:
- The Chart expects `DATABASE_URL` in `calcom-runtime-secrets`.
- The real `DATABASE_URL` is in `calcom-cluster-app` (key `uri`).

### The Solution: Secret Sync

To resolve this without forking the chart, we implemented a **Secret Sync** mechanism:

1.  **Component**: A small Deployment defined in `manifests/cal.com/secret-sync.yaml`.
2.  **Function**: It continuously monitors the CNPG secret (`calcom-cluster-app`).
3.  **Action**: When it detects the valid URI, it automatically **patches** the `calcom-runtime-secrets` secret to inject the correct `DATABASE_URL` key.

This ensures that:
- The Helm chart is satisfied (it finds the key where it expects it).
- Database credentials are always up-to-date (even after rotation).
- No manual intervention is needed.

### Troubleshooting

If you see `Authentication failed against database server` errors:
1.  Check if `calcom-secret-sync` pod is running in `calcom` namespace.
2.  Verify the `DATABASE_URL` key exists in `calcom-runtime-secrets`:
    ```bash
    kubectl get secret calcom-runtime-secrets -n calcom -o jsonpath="{.data.DATABASE_URL}" | base64 -d
    ```
3.  Restart the `calcom` pods if the secret was updated but the pod hasn't picked it up (env vars are loaded at startup).
