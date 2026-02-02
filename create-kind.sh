#!/bin/bash

set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

# --- Configuration ---
METALLB_VERSION="v0.14.9"
METALLB_MANIFEST="https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

FOO_CLUSTER="foo-cluster"
BAR_CLUSTER="bar-cluster"

FOO_METALLB_POOL_NAME="foo"
FOO_METALLB_RANGE="172.18.255.200-172.18.255.250"

BAR_METALLB_POOL_NAME="bar"
BAR_METALLB_RANGE="172.18.255.150-172.18.255.199"

export CTX_CLUSTER1="${FOO_CLUSTER}"
export CTX_CLUSTER2="${BAR_CLUSTER}"

# --- Functions ---

create_cluster() {
  local name=$1 config=$2
  # Delete existing cluster if it already exists (idempotency)
  if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    echo "Cluster '${name}' already exists, deleting it first..."
    kind delete cluster --name "${name}"
  fi
  # Remove stale kubeconfig context if it exists from a previous run
  kubectl config delete-context "${name}" 2>/dev/null || true
  kind create cluster --config="${config}"
  kubectl config rename-context "kind-${name}" "${name}"
}

install_metallb() {
  local ctx=$1 pool_name=$2 ip_range=$3

  kubectl apply -f "${METALLB_MANIFEST}" --context="${ctx}"
  kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=90s \
    --context="${ctx}"

  # Apply MetalLB IP address pool and L2 advertisement
  kubectl apply --context="${ctx}" -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ${pool_name}
  namespace: metallb-system
spec:
  addresses:
  - ${ip_range}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ${pool_name}-l2
  namespace: metallb-system
EOF
}

validate_metallb_subnet() {
  local subnets ipv4_subnet
  subnets=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' kind)
  # Extract only the IPv4 subnet (skip IPv6)
  ipv4_subnet=$(echo "${subnets}" | grep -oE '([0-9]+\.){3}[0-9]+/[0-9]+')
  echo "Docker 'kind' network IPv4 subnet: ${ipv4_subnet}"

  local base_prefix
  base_prefix=$(echo "${ipv4_subnet}" | cut -d'.' -f1-2)
  local expected_prefix="172.18"

  if [[ "${base_prefix}" != "${expected_prefix}" ]]; then
    echo "WARNING: Docker 'kind' network uses ${ipv4_subnet}, but MetalLB IP ranges assume ${expected_prefix}.x.x" >&2
    echo "         MetalLB may hand out unreachable IPs. Update the ranges to match your Docker network." >&2
    exit 1
  fi
}

# --- Main ---

# Create kind clusters
create_cluster "${FOO_CLUSTER}" "kind/kind-foo.yaml"
create_cluster "${BAR_CLUSTER}" "kind/kind-bar.yaml"

# Validate that the Docker network matches our hardcoded MetalLB ranges
validate_metallb_subnet

# Install MetalLB for east-west gateway load balancing
install_metallb "${CTX_CLUSTER1}" "${FOO_METALLB_POOL_NAME}" "${FOO_METALLB_RANGE}"
install_metallb "${CTX_CLUSTER2}" "${BAR_METALLB_POOL_NAME}" "${BAR_METALLB_RANGE}"

echo "Clusters '${FOO_CLUSTER}' and '${BAR_CLUSTER}' are ready."
echo "  CTX_CLUSTER1=${CTX_CLUSTER1}"
echo "  CTX_CLUSTER2=${CTX_CLUSTER2}"
