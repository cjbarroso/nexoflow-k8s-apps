# Architecture & Directory Structure

This repository follows a specific structure to organize Argo CD applications and their dependencies.

## Directory Structure

*   **`apps/`**: **The Primary Location for Applications.**
    *   This directory contains the self-contained definitions for each application.
    *   Each subfolder (e.g., `apps/nexoflow/`) typically contains:
        *   The Argo CD `Application` resource (e.g., `n8n-chart.yaml`).
        *   The Helm values file (e.g., `n8n-values-production.yaml`).
    *   **Rule**: **All new applications and their primary configurations must go here.**

*   **`manifests/`**: **Supporting Manifests.**
    *   This directory is for **additional required files** that cannot be easily managed within the primary Helm chart in `apps/`.
    *   Examples include:
        *   Raw Kubernetes manifests (Secrets, PVCs, Ingresses) that the Helm chart doesn't support or that need specific customization.
        *   Database cluster definitions (e.g., `nexoflow-pg-cluster.yaml`).
    *   **Rule**: Use `manifests/` only for supplementary resources. Do not put the main Application definition here.

*   **`bootstrap/`**: **Cluster Bootstrapping.**
    *   Contains the initial configurations to get the cluster and Argo CD up and running.
    *   Key files:
        *   `root-app.yaml`: The "App of Apps" that points Argo CD to the `apps/` directory.
        *   `repo-secret-v2.yaml`: The Source of Truth for the Git repository credentials.

## Secrets Management

Secrets are managed explicitly and are **not** stored in plain text in the repository (except for the bootstrap secret which appears to be a private/internal repo artifact).

*   **Repository Secret**: The credentials for Argo CD to access this Git repository are defined in **`bootstrap/repo-secret-v2.yaml`**.
    *   This is the **v2** version and is the current source of truth.
    *   It configures the SSH private key and `sshKnownHosts` for `192.168.5.80:23231`.

## Application Pattern

Most applications follow the "App of Apps" pattern:
1.  **Root App**: `bootstrap/root-app.yaml` manages the `apps/` directory.
2.  **Application Config**: Inside `apps/<app-name>/`, an Argo CD `Application` defines the source (Helm chart or Git path) and destination.
3.  **Values**: Helm values are stored alongside the application definition in `apps/` (or strictly for legacy/complex cases, referenced from `manifests/`).

**Note on Legacy/Hybrid configurations**: You may see some applications (like `nexoflow`) referencing files in `manifests/` from their `apps/` definition. This is acceptable for supplementary resources, but the goal is to keep the core definition in `apps/`.
