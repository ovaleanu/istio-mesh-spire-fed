# Istio Ambient Multi-Cluster Mesh

Multi-primary, multi-network Istio ambient mesh on two Kind clusters (`foo-cluster`, `bar-cluster`) with a shared root CA managed by cert-manager.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

`istioctl` is downloaded automatically by the install script.

## Steps

### 1. Create clusters

Creates two Kind clusters with MetalLB for LoadBalancer support (east-west gateways).

```bash
./create-kind.sh
```

### 2. Install cert-manager and shared root CA

Installs cert-manager on both clusters, generates a self-signed root CA on `foo-cluster`, exports it to `bar-cluster`, and issues Istio intermediate CA certificates (`cacerts`) on both.

```bash
./install-cert-manager.sh
```

### 3. Install Istio

Installs Istio ambient mode via Helm (base, istiod, istio-cni, ztunnel) on both clusters, exchanges remote secrets for cross-cluster discovery, and deploys east-west gateways.

```bash
./install-istio.sh
```

### 4. Deploy sample app

Deploys the helloworld service (v1 on `foo-cluster`, v2 on `bar-cluster`) and sleep clients on both clusters.

```bash
./helloworld/deploy.sh
```

### 5. Verify cross-cluster routing

Runs curl tests from both clusters. With `trafficDistribution: PreferClose`, local endpoints are preferred. After scaling down v1 on `foo-cluster`, traffic fails over to v2 on `bar-cluster`.

```bash
./helloworld/verify.sh
```

### Cleanup

Delete the helloworld workloads:

```bash
./helloworld/delete.sh
```

Destroy the Kind clusters:

```bash
./kind/destroy.sh
```

## Architecture

```
foo-cluster (foo-network)          bar-cluster (bar-network)
+--------------------------+       +--------------------------+
| istiod                   |       | istiod                   |
| ztunnel (per node)       |       | ztunnel (per node)       |
| istio-cni (per node)     |       | istio-cni (per node)     |
| east-west gw (:15008)   |<----->| east-west gw (:15008)    |
|   172.18.255.200         | HBONE |   172.18.255.150         |
+--------------------------+       +--------------------------+
| helloworld-v1            |       | helloworld-v2            |
| sleep                    |       | sleep                    |
+--------------------------+       +--------------------------+
```

- **Ambient mode**: No sidecars. ztunnel handles L4 mTLS; east-west gateways handle cross-network HBONE tunneling.
- **Shared root CA**: cert-manager generates a self-signed root CA, exported to both clusters so mTLS works cross-cluster.
- **Global services**: Services labeled `istio.io/global: "true"` are discoverable across clusters via the ServiceScope API.
- **Traffic distribution**: `trafficDistribution: PreferClose` keeps traffic local when local endpoints exist, failing over cross-cluster only when needed.
