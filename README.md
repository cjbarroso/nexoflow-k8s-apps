# My apps
Instalar argocd core

```sh

 kubectl config set-context --current --namespace=argocd

```


# Source of truth

GitHub is the GitOps source of truth:

```sh
git remote add origin https://github.com/cjbarroso/nexoflow-k8s-apps.git
```

Argo CD reads the same GitHub repository through `bootstrap/root-app.yaml`.

## Docs

- `docs/05-VAULTWARDEN-UPDATE-NOTES.md`: Vaultwarden image update notes and verification commands.
