# kubernetes-test-one

A minimal Python HTTP server project intended as a Kubernetes deployment testbed. It exposes a simple JSON endpoint on port `8000`, includes a multi-stage `Dockerfile`, and ships Kubernetes manifests for deploying the app and related cluster resources.

Then it took on a life of its own. As I migrated a variety of projects that I have built over decades, I started to aggregate the Kubernetes "infrastructure" bits here. The idea is that if I want to stand up a brand new cluster, recover a destroyed environment, or update configurations, I've got all the deployment information here (well, not secrets).

So this started out as a "How can I run Python?" project and ended up being the collector for:
- a Postgres database cluster
- a MetalLB IP address pool
- ExternalDNS
- tweaks to CoreDNS to provide resiliency
- a Longhorn storage deployment

I did get the Python HTTP server running. It helped me learn about deploying to a multi-node cluster. That value was eclipsed by the value of centralized infrastructure.

## Features

- Simple threaded Python HTTP server in `app.py`
- Returns JSON with `status`, `message`, current `time`, and the Kubernetes node name
- Multi-stage Docker build in `Dockerfile`
- Kubernetes Deployment + Service manifest in `k8s/deployment.yaml`
- RBAC manifest for node access in `k8s/rbac.yaml`
- Example Jenkins pipeline in `Jenkinsfile`
- Optional external DNS manifest in `k8s/external-dns-linode.yaml`

## Prerequisites

- Python 3.11 or later
- Docker and optionally Buildx for multi-arch builds
- Kubernetes cluster with `kubectl` configured
- Optional: Jenkins for CI/CD
- Optional: Linode API token if using `external-dns`

## Local run

1. Install dependencies:

```powershell
pip install -r requirements.txt
```

2. Start the server:

```powershell
python app.py
```

3. Open `http://localhost:8000` in a browser or use curl:

```powershell
curl http://localhost:8000
```

## Docker build

Build the image locally:

```powershell
docker build -t python-server:local .
```

Run the container:

```powershell
docker run --rm -p 8000:8000 python-server:local
```

## Kubernetes deployment

This repository includes both the application deployment and several cluster-level manifests for a bare-metal Kubernetes environment.

### Application resources

- `k8s/rbac.yaml` - creates the `node-reader-sa` ServiceAccount, ClusterRole, and ClusterRoleBinding.
  - Required before the app deployment because `k8s/deployment.yaml` uses `serviceAccountName: node-reader-sa`.
- `k8s/deployment.yaml` - deploys `python-server-deployment` and a `NodePort` Service.
  - The Deployment runs `app.py` and sets `NODE_NAME` from the pod field reference.
  - The Service exposes port `80` externally on `nodePort: 30000` and forwards traffic to container port `8000`.

Apply the app manifests:

```powershell
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/deployment.yaml
```

Update the Deployment image if you built a custom registry image:

```powershell
kubectl set image deployment/python-server-deployment app-container=<registry>/python-server:<tag>
```

Access the application from any node:

```powershell
curl http://<node-ip>:30000
```

### Cluster infrastructure manifests

These manifests are useful when running on bare-metal or custom on-prem Kubernetes clusters.

- `k8s/metal-lb-config.yaml` - MetalLB IP pool and L2 advertisement for bare-metal LoadBalancer support.
- `k8s/external-dns-linode.yaml` - deploys ExternalDNS configured for Linode DNS.
  - Requires a Kubernetes secret named `linode-api-token` with a `token` key.
  - Uses `--domain-filter=siwko.org` and manages DNS records for Services/Ingresses.
- `k8s/coredns-deployment.yaml` - patches the `kube-system` CoreDNS Deployment to enforce physical-host spreading and stronger scheduling behavior.
  - This is a resilience fix for cluster DNS rather than the app itself.

### PostgreSQL cluster

This repo also includes manifests for a CloudNativePG PostgreSQL cluster.

- `k8s/cnpg-operator.yaml` - installs the CloudNativePG operator and CRDs into `cnpg-system`.
- `k8s/prod-postgres-cluster.yaml` - creates a `Cluster` custom resource named `prod-postgres`.
  - Configured for 4 instances with required anti-affinity across `db-host-group`.
  - Uses `ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie` and 10Gi storage.
- `k8s/postgres-lb.yaml` - exposes the primary Postgres instance via a `LoadBalancer` Service.
  - Includes an ExternalDNS annotation for `postgres.siwko.org`.

### Longhorn storage

These manifests deploy Longhorn for cluster storage and define an HA storage class.

- `k8s/longhorn.yaml` - installs the Longhorn storage stack into the `longhorn-system` namespace.
  - This file contains namespace, CRDs, ServiceAccounts, ConfigMaps, priority class, and the Longhorn control plane resources.
- `k8s/longhorn-ha-storageclass.yaml` - defines a custom `longhorn-ha` StorageClass.
  - Uses `driver.longhorn.io`, 2 replicas, and hard zone anti-affinity to spread replicas across physical hosts.

### Notes on deploy order

A typical bare-metal deployment order is:

1. `kubectl apply -f k8s/metal-lb-config.yaml`
2. `kubectl apply -f k8s/rbac.yaml`
3. `kubectl apply -f k8s/external-dns-linode.yaml` (optional)
4. `kubectl apply -f k8s/longhorn.yaml`
5. `kubectl apply -f k8s/longhorn-ha-storageclass.yaml`
6. `kubectl apply -f k8s/cnpg-operator.yaml`
7. `kubectl apply -f k8s/prod-postgres-cluster.yaml`
8. `kubectl apply -f k8s/postgres-lb.yaml`
9. `kubectl apply -f k8s/coredns-deployment.yaml` (cluster DNS fix)
10. `kubectl apply -f k8s/deployment.yaml`

## Jenkins pipeline

The included `Jenkinsfile` demonstrates a pipeline with the following stages:

- checkout source code
- build and push a multi-arch Docker image using Buildx
- deploy Kubernetes manifests
- label cluster nodes
- install cluster infrastructure like MetalLB, ExternalDNS, CNPG, and Longhorn

Customize the `REGISTRY_DOMAIN`, `IMAGE_NAME`, and `IMAGE_TAG` values before use.

## Notes

- `k8s/deployment.yaml` sets `NODE_NAME` from the pod field reference so the app can report its running node.
- `k8s/rbac.yaml` creates a service account and cluster role binding used by the Deployment.
- The app currently does not require a database or persistent storage.
- `kgetnodes.py` is a helper script for listing Kubernetes nodes from local kubeconfig or in-cluster config.

## Project layout

- `app.py` — threaded HTTP server
- `Dockerfile` — multi-stage container build
- `requirements.txt` — Python dependencies
- `k8s/` — Kubernetes manifests
- `Jenkinsfile` — CI/CD pipeline example
- `kgetnodes.py` — Kubernetes node listing helper

