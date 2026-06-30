# Kubernetes Environment

This directory contains all the kubernetes config files required to maintain my homelab. To deploy it, you'll need a few more components that I'll detail below.

## k3s cluster

To make Kubernetes cluster deployment easier, I chose to use k3s which comes bundled with Traefik and Helm. You can initialize the first node using:

```bash
curl -sfL https://get.k3s.io | sh -s - server --token=<CLUSTER_SETUP_TOKEN> --secrets-encryption --cluster-init
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

Apply `kube/traefik/metallb-config.yaml`. The IP pool must be a range of free, unassigned IPs that are outside your DHCP pool and not assigned to any node:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.5.10-10.0.5.20
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

### Configure Traefik for source IP preservation

```bash
kubectl apply -f kube/traefik/
```

This ensures Traefik sees the real client IP instead of the pod/node IP.

## Storage configuration

To store permanent data, I use LongHorn which allows me to have shared storage between all my nodes. Long Horn requires a package to be installed on every node:
```bash
sudo dnf install iscsi-initiator-utils -y
sudo systemctl enable --now iscsid
```

## Monitoring Support (kube-state-metrics)

To feed Kubernetes resource state metrics (like pod phases, container restarts, node conditions) to Prometheus, you must deploy `kube-state-metrics` in the cluster:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-state-metrics prometheus-community/kube-state-metrics -n kube-system
```