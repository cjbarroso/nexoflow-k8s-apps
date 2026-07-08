# kube-vip — control-plane VIP (applied OUT-OF-BAND, not via Argo)

`kube-vip.yaml` provides the floating control-plane virtual IP **`192.168.5.79`**
for the 3-node embedded-etcd cluster (kube-vip **v1.2.1**, ARP/layer-2 mode,
leader election, `svc_enable=false`). `vip_interface` is intentionally **empty**
so each node auto-detects its own NIC (they differ: `enp5s0` / `eno1` / `enp2s0`).

## Why this lives in `bootstrap/`, not `apps/`

kube-vip **fronts the Kubernetes API that Argo CD itself depends on**, so it must
NOT be managed by Argo (a sync blip on the thing serving the API would be a
foot-gun). It is applied **manually**, like the rest of `bootstrap/`.

## Apply / recover

```bash
kubectl apply -f bootstrap/kube-vip/kube-vip.yaml
# verify: 3 pods Running in kube-system, VIP answers, API reachable via it
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-ds -o wide
kubectl --server https://192.168.5.79:6443 get nodes
```

For a from-scratch cluster rebuild, apply this right after the control plane is
up (before/with Argo CD). Each k3s server's API cert must include the VIP in its
`tls-san` (set in `/etc/rancher/k3s/config.yaml` on every server:
`tls-san: [192.168.5.79, <node-ip>, <hostname>]`).

Deployed live 2026-07-08 (this file is the reference copy for disaster recovery).
