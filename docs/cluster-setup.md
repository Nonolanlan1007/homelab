# Kubernetes Environment

This directory contains all the kubernetes config files required to maintain my homelab. To deploy it, you'll need a few more components that I'll detail below.

## k3s cluster

To make Kubernetes cluster deployment easier, I chose to use k3s which comes bundled with Traefik and Helm. You can initialize the first node using:

```bash
curl -sfL https://get.k3s.io | sh -s - server --token=<CLUSTER_SETUP_TOKEN> --secrets-encryption --cluster-init --disable traefik
```

You can then add 2 more nodes using the following command:
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<YOUR_NODE_TOKEN> sh -s - server --server https://<IP_OF_K3S_0>:6443 --secrets-encryption
```

## Load Balancer (MetalLB)

k3s ships with its own load balancer (servicelb/klipper) which does not preserve real client IPs. MetalLB is used instead to get proper L2 announcements and source IP preservation.

### Disable k3s servicelb

On every node, add the following to `/etc/rancher/k3s/config.yaml` (create if missing):

```yaml
disable:
  - servicelb
```

Then restart k3s:
```bash
sudo systemctl restart k3s
```

### Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
kubectl wait -n metallb-system deployment controller --for=condition=Available --timeout=120s
```

### Configure MetalLB

Apply `platform/metallb/metallb-config.yaml`. The IP pool must be a range of free, unassigned IPs that are outside your DHCP pool and not assigned to any node:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.1.10-10.0.1.10
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

### Configure Traefik for source IP preservation

```bash
kubectl apply -f platform/traefik/
```

This ensures Traefik sees the real client IP instead of the pod/node IP.

## Storage configuration

To store permanent data, I use k3s's bundled `rancher.io/local-path` provisioner via a custom `local-path-retain` StorageClass (`platform/local-path/storage-class.yaml`, `reclaimPolicy: Retain` so deleting a PVC never silently deletes its data). No extra provisioner install is needed — it ships with k3s. Since it's backed by a hostPath directory on whichever node the consuming pod first lands on (`volumeBindingMode: WaitForFirstConsumer`), a PVC's data is pinned to that node from then on; this is a non-issue on a single-node cluster, but matters if more nodes get added later.

Several apps also mount statically-provisioned NFS `PersistentVolume`s (backed by a NAS). Every node needs the NFS client installed:
```bash
sudo dnf install -y nfs-utils
```

## Monitoring Support (kube-state-metrics)

To feed Kubernetes resource state metrics (like pod phases, container restarts, node conditions) to Prometheus, you must deploy `kube-state-metrics` in the cluster:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-state-metrics prometheus-community/kube-state-metrics -n kube-system
```