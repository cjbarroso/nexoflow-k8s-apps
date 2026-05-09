# My apps
Instalar argocd core

```sh

 kubectl config set-context --current --namespace=argocd

```


# Instalar https://github.com/charmbracelet/soft-serve


# Para crear el repo
git remote add origin ssh://192.168.5.80:23231/nexoflow-k8s-apps
Here

# Para que ande la conexion al repo
argocd cert add-ssh --batch --from ~/.ssh/known_hosts

## Docs

- `docs/05-VAULTWARDEN-UPDATE-NOTES.md`: Vaultwarden image update notes, GitOps source of truth, Soft Serve behavior, and verification commands.
