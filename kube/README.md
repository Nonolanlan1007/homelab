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

To store permanent data, I use an external NFS server which allows me to have shared storage between all my nodes.
Add helm repo
```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
```

Install NFS on each node:
```bash
sudo dnf install nfs-utils -y
```

Add Common storage
```bash
helm install common-storage nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=X.X.X.X \
    --set nfs.path=/nfs/path \
    --set storageClass.name=common-storage-client \
    --set storageClass.provisionerName=k8s-sigs.io/common-storage \
    --set storageClass.accessModes=ReadWriteMany \
    --set storageClass.reclaimPolicy=Retain \
    --set storageClass.pathPattern='${.PVC.name}' \
    --set storageClass.defaultClass=true
```
