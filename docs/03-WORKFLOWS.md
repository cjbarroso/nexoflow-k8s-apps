# Workflows & Guidelines

## Adding a New Application

When adding a new workload to the cluster, follow these steps to ensure consistency:

1.  **Create the App Directory**:
    Create a new directory in `apps/<app-name>/`.
    ```bash
    mkdir -p apps/my-new-app
    ```

2.  **Define the Application**:
    Create two key files in this directory:
    *   `values-production.yaml`: Your Helm values.
    *   `my-new-app-chart.yaml` (or `app.yaml`): The Argo CD Application definition.

3.  **Follow the `APP-STRUCTURE` Guide**:
    Refer to `docs/06-APP-STRUCTURE.md` for the detailed checklist and boilerplate code. It contains the standard templates for the `Application` manifest.

4.  **Handling Extra Manifests**:
    If your application requires resources not covered by the Helm chart (e.g., a specific pure-manifest Secret or a custom PVC adjustment), place these files in `manifests/<app-name>/`.
    *   Then, update your Argo CD `Application` to include `manifests/<app-name>` as a **second source**.

    *Example (Multi-source App)*:
    ```yaml
    sources:
      - chart: my-chart
        # ... helm config ...
      - repoURL: 'https://github.com/cjbarroso/nexoflow-k8s-apps.git'
        path: manifests/my-new-app
        targetRevision: master
    ```

## Development Workflow

1.  **Make Changes**: Edit the YAML files in `apps/` or `manifests/`.
2.  **Commit & Push**:
    ```bash
    git add .
    git commit -m "feat: Add my new app"
    git push origin master
    ```
3.  **Sync**:
    Argo CD will automatically detect changes (usually within 3 minutes). You can manually sync via the UI or CLI if needed:
    ```bash
    argocd app sync my-new-app
    ```

## Secrets

*   **Repository Access**: Argo CD reads the public GitHub repository defined in `bootstrap/root-app.yaml`. If the repository becomes private, update `bootstrap/repo-secret.yaml` with GitHub credentials or a deploy key.
*   **App Secrets**: Do not commit actual secrets (passwords, API keys) to Git unless they are encrypted (e.g., SealedSecrets) or you are using an external secret store.
