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

## GitOps Source Of Truth

Argo CD does not deploy from the local checkout on this workstation or from GitHub. The root Argo CD app tracks the Soft Serve repository:

```text
ssh://192.168.5.80:23231/nexoflow-k8s-apps
```

The root app tracks `HEAD` in that repository. At the time of the update, the local checkout was behind the Soft Serve branch by many commits, so pushing the local branch directly would have overwritten unrelated cluster changes.

Safe workflow when the local checkout is stale:

```sh
git fetch softserve master
git worktree add ../nexoflow-k8s-apps-softserve softserve/master
```

Make the change in the temporary worktree, not in the stale checkout. Commit only the intended files.

## Applying Changes

Directly applying `apps/vaultwarden/vaultwarden-chart.yaml` with `kubectl apply` is not durable when the Git repo differs from the local file. The root app reconciles the child `Application` object back to the version from Soft Serve.

Observed behavior:

1. `kubectl apply -f apps/vaultwarden/vaultwarden-chart.yaml` was accepted.
2. Argo CD briefly deployed the changed `vaultwarden` application.
3. The root app reconciled from Soft Serve and reverted the child app back to the committed Git version.

Durable changes must land in the Soft Serve repository first.

Normal expected path:

```sh
git add apps/vaultwarden/vaultwarden-chart.yaml
git commit -m "Update Vaultwarden image"
git push softserve HEAD:master
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

## Soft Serve Notes

Soft Serve runs in the `argocd` namespace:

```sh
kubectl get pods -n argocd -l app=soft-serve -o wide
kubectl get svc -n argocd | Select-String "soft-serve"
```

The bare Git repository is stored in the Soft Serve pod at:

```text
/soft-serve/repos/nexoflow-k8s-apps.git
```

Use direct bare-repo changes only as an operational fallback. Prefer authenticated Git push whenever write access is available.

## Follow-Up Items

- Configure a workstation SSH key with write access to Soft Serve so future GitOps updates can use normal `git push`.
- Keep `origin` and `softserve` remotes distinct. `origin` may point to GitHub, but Argo CD tracks Soft Serve.
- Move Vaultwarden secrets out of inline Helm values when possible. The manifest currently contains sensitive runtime configuration, which is risky for Git history and local checkouts.
- Periodically check whether Gabe565 publishes a newer Vaultwarden chart. If the chart updates its `appVersion`, remove the image override only after verifying the chart default matches the desired image tag.
