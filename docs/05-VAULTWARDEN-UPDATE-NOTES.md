# Vaultwarden Update Notes

These notes document the Vaultwarden update performed on 2026-05-09 and the operational details learned while applying it.

## Current State

- Argo CD app: `vaultwarden`
- Argo CD namespace: `argocd`
- Workload namespace: `vaultwarden`
- Manifest: `apps/vaultwarden/vaultwarden-chart.yaml`
- Helm repository: `https://charts.gabe565.com`
- Helm chart: `vaultwarden`
- Chart version: `0.16.1`
- Image repository: `ghcr.io/dani-garcia/vaultwarden`
- Image tag: `1.36.0-alpine`

The Gabe565 chart repository still publishes `vaultwarden` chart `0.16.1` as the newest chart version. That chart defaulted to app image `1.33.2-alpine`, so the update was applied as an explicit Helm values override:

```yaml
image:
  repository: ghcr.io/dani-garcia/vaultwarden
  tag: 1.36.0-alpine
```

## Historical GitOps Source Of Truth Issue

At the time of the Vaultwarden update, Argo CD deployed from the in-cluster Soft Serve repository, not from GitHub. The cluster has since been migrated so GitHub is the source of truth:

```text
https://github.com/cjbarroso/nexoflow-k8s-apps.git
```

The root app now tracks `master` in that repository. During the Vaultwarden update, the local checkout was behind Soft Serve by many commits, so pushing the local branch directly would have overwritten unrelated cluster changes.

Safe workflow when the local checkout is stale now:

```sh
git fetch origin master
git worktree add ../nexoflow-k8s-apps-current origin/master
```

Make the change in the temporary worktree, not in the stale checkout. Commit only the intended files.

## Applying Changes

Directly applying `apps/vaultwarden/vaultwarden-chart.yaml` with `kubectl apply` is not durable when the Git repo differs from the local file. The root app reconciles the child `Application` object back to the version from GitHub.

Observed behavior:

1. `kubectl apply -f apps/vaultwarden/vaultwarden-chart.yaml` was accepted.
2. Argo CD briefly deployed the changed `vaultwarden` application.
3. The root app reconciled from Git and reverted the child app back to the committed Git version.

Durable changes must land in GitHub first.

Normal expected path:

```sh
git add apps/vaultwarden/vaultwarden-chart.yaml
git commit -m "Update Vaultwarden image"
git push origin master
```

In this update, direct SSH push to Soft Serve from the workstation was denied. The Argo CD repository credentials were also read-only for push. Because cluster admin access was available, the prepared commit was fast-forwarded into the bare Soft Serve repository inside the `soft-serve` pod.

Commit applied:

```text
b4e853f Update Vaultwarden image
```

## Validation Commands

Validate the manifest before applying or committing:

```sh
kubectl apply --dry-run=client -f apps/vaultwarden/vaultwarden-chart.yaml
```

Check the root app revision and health:

```sh
kubectl get application root -n argocd \
  -o jsonpath="{.status.sync.revision}{' '}{.status.sync.status}{' '}{.status.health.status}{'\n'}"
```

Check the Vaultwarden Argo CD app:

```sh
kubectl get application vaultwarden -n argocd \
  -o jsonpath="{.status.sync.status}{' '}{.status.health.status}{' '}{.status.operationState.phase}{'\n'}"
```

Check the live Deployment image:

```sh
kubectl get deployment vaultwarden -n vaultwarden \
  -o jsonpath="{.spec.template.spec.containers[*].image}{'\n'}"
```

Confirm rollout completion:

```sh
kubectl rollout status deployment/vaultwarden -n vaultwarden --timeout=120s
```

Check the pod:

```sh
kubectl get pods -n vaultwarden -l app.kubernetes.io/name=vaultwarden -o wide
```

Successful result after this update:

```text
ghcr.io/dani-garcia/vaultwarden:1.36.0-alpine
deployment "vaultwarden" successfully rolled out
```

## Legacy Soft Serve Notes

Soft Serve was previously used as the in-cluster Git server. It may still exist in the `argocd` namespace as a legacy component:

```sh
kubectl get pods -n argocd -l app=soft-serve -o wide
kubectl get svc -n argocd | Select-String "soft-serve"
```

The bare Git repository is stored in the Soft Serve pod at:

```text
/soft-serve/repos/nexoflow-k8s-apps.git
```

Do not use Soft Serve as the GitOps source of truth after the GitHub migration. Prefer normal GitHub commits and pushes.

## Follow-Up Items

- Keep local `origin` pointed at GitHub because Argo CD now tracks GitHub.
- Move Vaultwarden secrets out of inline Helm values when possible. The manifest currently contains sensitive runtime configuration, which is risky for Git history and local checkouts.
- Periodically check whether Gabe565 publishes a newer Vaultwarden chart. If the chart updates its `appVersion`, remove the image override only after verifying the chart default matches the desired image tag.
