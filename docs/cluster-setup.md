# Cluster setup

How to rebuild the homelab from bare nodes. Most of the cluster is reconciled by Argo CD from this
repository, but a few things must exist before Argo CD can take over, and a few critical apps are
synced by hand on purpose.

Bootstrap order:

1. [k3s](#1-k3s) on every node
2. [MetalLB](#2-metallb) controller
3. [kube-state-metrics](#3-kube-state-metrics)
4. [Argo CD](#4-argo-cd), then the root application
5. [External Secrets and OpenBao](#5-external-secrets-and-openbao), then initialising OpenBao
6. [Traefik](#6-traefik)
7. [App secrets](#7-app-secrets) through OpenTofu

## 1. k3s

The bundled Traefik is disabled because Traefik is deployed as an Argo CD Helm app. The bundled
servicelb (klipper) is disabled because it does not preserve client source IPs, and MetalLB replaces
it. These settings must be the same on every server node, so put them in
`/etc/rancher/k3s/config.yaml` on each node before installing:

```yaml
secrets-encryption: true
disable:
  - traefik
  - servicelb
```

Initialise the first node:

```bash
curl -sfL https://get.k3s.io | sh -s - server --cluster-init --token=<CLUSTER_TOKEN>
```

Join additional server nodes with the same token:

```bash
curl -sfL https://get.k3s.io | sh -s - server --server https://<IP_OF_FIRST_NODE>:6443 --token=<CLUSTER_TOKEN>
```

Several apps mount statically provisioned NFS `PersistentVolume`s from the NAS, so every node needs
the NFS client:

```bash
sudo dnf install -y nfs-utils
```

## 2. MetalLB

The MetalLB controller and CRDs are installed once by hand:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
kubectl wait -n metallb-system deployment controller --for=condition=Available --timeout=120s
```

Its configuration ([`platform/metallb/metallb-config.yaml`](../platform/metallb/metallb-config.yaml))
is applied by Argo CD later. The pool must contain free IPs that are outside the DHCP range and not
assigned to any node. Traefik's `LoadBalancer` service takes `10.0.1.10`.

## 3. kube-state-metrics

Prometheus scrapes kube-state-metrics for pod phases, restarts and node conditions:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-state-metrics prometheus-community/kube-state-metrics -n kube-system
```

## 4. Argo CD

Install Argo CD with the same release name and values that its own Argo CD app uses. From then on,
Argo CD manages itself.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace -f apps/helm/argocd/values.yaml
kubectl apply -f argocd/bootstrap/root.yaml
```

The root application creates the `homelab` project, the `platform` app and both ApplicationSets.
The `platform` app and every app under `apps/manifests/` sync automatically. Apps that need secrets
stay degraded until step 7, then recover on their own.

The Helm apps for Argo CD, External Secrets, OpenBao and Traefik have `autoSync: false`, so a bad
commit cannot take down the infrastructure everything else depends on. Sync them by hand, either
from the UI or with `argocd app sync <name>`. Until Traefik is up, reach the UI with a port-forward:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

## 5. External Secrets and OpenBao

Sync `external-secrets` first, then `openbao`. OpenBao starts sealed. Initialise and unseal it, and
store the unseal keys and root token somewhere outside the cluster:

```bash
kubectl exec -it openbao-0 -- bao operator init
kubectl exec -it openbao-0 -- bao operator unseal   # repeat until the threshold is reached
```

There is no auto-unseal, so OpenBao has to be unsealed again every time its pod restarts.

Enable the KV store and Kubernetes auth from inside the pod. Running in the pod lets OpenBao use its
own ServiceAccount to validate app tokens.

```bash
kubectl exec -it openbao-0 -- sh
export BAO_TOKEN=<ROOT_TOKEN>
bao secrets enable -path=secret kv-v2
bao auth enable kubernetes
bao write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
```

## 6. Traefik

OpenTofu talks to OpenBao through `https://openbao.lazyduck.fr`, which needs Traefik running, and
Traefik needs its Cloudflare DNS token from OpenBao. To break the loop, create Traefik's policy, role
and secret by hand in the same shell. OpenTofu takes them over in step 7.

```bash
bao policy write traefik - <<'EOF'
path "secret/data/homelab/traefik" {
  capabilities = ["read"]
}
EOF
bao write auth/kubernetes/role/traefik \
  bound_service_account_names=traefik-sa \
  bound_service_account_namespaces=kube-system \
  token_policies=traefik \
  token_ttl=3600
bao kv put secret/homelab/traefik cf-token=<CLOUDFLARE_DNS_API_TOKEN>
```

Then sync `traefik`. It obtains Let's Encrypt certificates through a Cloudflare DNS-01 challenge,
and the cluster-wide middlewares in [`platform/traefik/`](../platform/traefik/) (for example
`internal-only`) are already applied by the `platform` app.

Client IP preservation is configured in
[`apps/helm/traefik/values.yaml`](../apps/helm/traefik/values.yaml): `externalTrafficPolicy: Local`
on the service, plus PROXY protocol trusted only from the upstream proxy.

## 7. App secrets

With OpenBao reachable through Traefik, apply the per-app policies and Kubernetes auth roles from
[`tofu/openbao/`](../tofu/openbao/). This also reconciles the Traefik policy and role created by
hand.

```bash
cd tofu/openbao
export VAULT_TOKEN=<ROOT_TOKEN>
tofu init
tofu apply
```

Write each app's secrets to `secret/homelab/<app>`. The keys an app expects are the environment
variables and `secretKeyRef`s in its deployment.

```bash
bao kv put secret/homelab/<app> KEY=value ...
```

External Secrets refreshes every minute, so the apps start as soon as their secrets exist.

## Storage notes

Persistent data uses k3s's bundled `rancher.io/local-path` provisioner through a custom
`local-path-retain` StorageClass ([`platform/local-path/`](../platform/local-path/)).
`reclaimPolicy: Retain` means deleting a PVC never deletes its data.

The volumes are hostPath directories under `/var/lib/rancher/k3s/storage`, created on whichever node
the consuming pod lands on first (`volumeBindingMode: WaitForFirstConsumer`). From then on, that
PVC and its pods are pinned to that node. The `master-vnic` node is excluded from local-path storage
in the provisioner config.
