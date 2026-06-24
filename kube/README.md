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

