#!/bin/bash

set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

# --- Configuration ---
ISTIO_VERSION="1.28.3"
GATEWAY_API_VERSION="v1.4.1"
GATEWAY_API_CRDS="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
MESH_ID="devup-mesh"
ROLLOUT_TIMEOUT="120s"

CTX_CLUSTER1="foo-cluster"
CTX_CLUSTER2="bar-cluster"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"

# --- Functions ---

ensure_istioctl() {
  if [[ -x "${BIN_DIR}/istioctl" ]]; then
    local current_version
    current_version=$("${BIN_DIR}/istioctl" version --remote=false 2>/dev/null || true)
    if [[ "${current_version}" == *"${ISTIO_VERSION}"* ]]; then
      echo "istioctl ${ISTIO_VERSION} already available in ${BIN_DIR}."
      return 0
    fi
  fi

  echo "Downloading istioctl ${ISTIO_VERSION}..."
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "ERROR: Unsupported architecture '${arch}'." >&2; return 1 ;;
  esac

  local url="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-${os}-${arch}.tar.gz"
  mkdir -p "${BIN_DIR}"
  curl -fsSL "${url}" | tar -xz -C "${BIN_DIR}"
  chmod +x "${BIN_DIR}/istioctl"
  echo "istioctl ${ISTIO_VERSION} installed to ${BIN_DIR}/istioctl."
}

ensure_helm_repo() {
  echo "Adding Istio Helm repository..."
  helm repo add istio https://istio-release.storage.googleapis.com/charts 2>/dev/null || true
  helm repo update istio
}

install_helm_charts() {
  local ctx=$1 cluster_name=$2 network=$3

  echo "Installing Istio ${ISTIO_VERSION} (ambient) via Helm on context '${ctx}' (network: ${network})..."

  # 1. Base CRDs
  helm upgrade --install istio-base istio/base \
    -n istio-system --kube-context "${ctx}" \
    --version "${ISTIO_VERSION}" --wait

  # 2. istiod (control plane)
  cat <<EOF | helm upgrade --install istiod istio/istiod \
    -n istio-system --kube-context "${ctx}" \
    --version "${ISTIO_VERSION}" \
    -f - --wait
profile: ambient
global:
  meshID: ${MESH_ID}
  multiCluster:
    clusterName: ${cluster_name}
  network: ${network}
pilot:
  env:
    AMBIENT_ENABLE_MULTI_NETWORK: "true"
    ENABLE_WILDCARD_HOST_SERVICE_ENTRIES_FOR_TLS: "true"
EOF

  # 3. istio-cni
  cat <<EOF | helm upgrade --install istio-cni istio/cni \
    -n istio-system --kube-context "${ctx}" \
    --version "${ISTIO_VERSION}" \
    -f - --wait
profile: ambient
global:
  meshID: ${MESH_ID}
  multiCluster:
    clusterName: ${cluster_name}
  network: ${network}
EOF

  # 4. ztunnel
  cat <<EOF | helm upgrade --install ztunnel istio/ztunnel \
    -n istio-system --kube-context "${ctx}" \
    --version "${ISTIO_VERSION}" \
    -f - --wait
global:
  meshID: ${MESH_ID}
  multiCluster:
    clusterName: ${cluster_name}
  network: ${network}
EOF

  # Verify rollouts
  kubectl -n istio-system rollout status deployment/istiod --timeout="${ROLLOUT_TIMEOUT}" --context="${ctx}"
  kubectl -n istio-system rollout status daemonset/ztunnel --timeout="${ROLLOUT_TIMEOUT}" --context="${ctx}"
  kubectl -n istio-system rollout status daemonset/istio-cni-node --timeout="${ROLLOUT_TIMEOUT}" --context="${ctx}"

  # Label namespace with network (after Helm installs, matching upstream order)
  kubectl label namespace istio-system topology.istio.io/network="${network}" \
    --overwrite --context="${ctx}"

  echo "Istio Helm charts installed on '${ctx}'."
}

create_remote_secret() {
  local src_ctx=$1 src_name=$2 dst_ctx=$3

  local control_plane="${src_name}-control-plane"
  local server
  server="https://$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${control_plane}"):6443"

  # Create a long-lived service account token
  kubectl apply --context "${src_ctx}" -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: istio-reader-service-account-istio-remote-secret-token
  namespace: istio-system
  annotations:
    kubernetes.io/service-account.name: istio-reader-service-account
type: kubernetes.io/service-account-token
EOF

  # Wait for token generation
  echo "Waiting for service account token on '${src_ctx}'..."
  until kubectl get --context "${src_ctx}" -n istio-system secret \
    istio-reader-service-account-istio-remote-secret-token \
    -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; do
    sleep 1
  done

  local token ca_b64
  token="$(kubectl get --context "${src_ctx}" -n istio-system secret \
    istio-reader-service-account-istio-remote-secret-token \
    -o jsonpath='{.data.token}' | base64 -d)"
  ca_b64="$(kubectl get --context "${src_ctx}" -n istio-system secret \
    istio-reader-service-account-istio-remote-secret-token \
    -o jsonpath='{.data.ca\.crt}')"

  # Create the remote secret on the destination cluster
  kubectl apply --context "${dst_ctx}" --server-side -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: istio-remote-secret-${src_name}
  namespace: istio-system
  labels:
    istio/multiCluster: "true"
  annotations:
    networking.istio.io/cluster: ${src_name}
stringData:
  ${src_name}: |
    apiVersion: v1
    kind: Config
    clusters:
    - name: ${src_name}
      cluster:
        server: ${server}
        certificate-authority-data: ${ca_b64}
    contexts:
    - name: ${src_name}
      context:
        cluster: ${src_name}
        user: ${src_name}
    current-context: ${src_name}
    users:
    - name: ${src_name}
      user:
        token: ${token}
EOF

  echo "Remote secret for '${src_name}' created on '${dst_ctx}'."
}

deploy_eastwest_gateway() {
  local ctx=$1 network=$2

  kubectl apply --context="${ctx}" --server-side -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: "${network}"
spec:
  gatewayClassName: istio-east-west
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
      tls:
        mode: Terminate
        options:
          gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
EOF
}

# --- Main ---

ensure_istioctl
export PATH="${BIN_DIR}:${PATH}"

ensure_helm_repo

# 1. Gateway API CRDs on both clusters
echo "Installing Gateway API CRDs ${GATEWAY_API_VERSION} on both clusters..."
kubectl apply --server-side --force-conflicts -f "${GATEWAY_API_CRDS}" --context="${CTX_CLUSTER1}"
kubectl apply --server-side --force-conflicts -f "${GATEWAY_API_CRDS}" --context="${CTX_CLUSTER2}"

# 2. Ensure istio-system namespace exists on both clusters
#    (cacerts should already be present from install-cert-manager.sh)
kubectl create namespace istio-system --context="${CTX_CLUSTER1}" --dry-run=client -o yaml \
  | kubectl apply --context="${CTX_CLUSTER1}" -f -
kubectl create namespace istio-system --context="${CTX_CLUSTER2}" --dry-run=client -o yaml \
  | kubectl apply --context="${CTX_CLUSTER2}" -f -

# 3. Helm install on foo-cluster (base, istiod, cni, ztunnel) then label namespace
install_helm_charts "${CTX_CLUSTER1}" "foo-cluster" "foo-network"

# 4. Helm install on bar-cluster (base, istiod, cni, ztunnel) then label namespace
install_helm_charts "${CTX_CLUSTER2}" "bar-cluster" "bar-network"

# 5. Exchange remote secrets for multi-cluster discovery
create_remote_secret "${CTX_CLUSTER1}" "foo-cluster" "${CTX_CLUSTER2}"
create_remote_secret "${CTX_CLUSTER2}" "bar-cluster" "${CTX_CLUSTER1}"

# 6. Deploy east-west gateways on both clusters
deploy_eastwest_gateway "${CTX_CLUSTER1}" "foo-network"
deploy_eastwest_gateway "${CTX_CLUSTER2}" "bar-network"

# 7. Wait for east-west gateway external IPs
for ctx in "${CTX_CLUSTER1}" "${CTX_CLUSTER2}"; do
  echo "Waiting for east-west gateway external IP on '${ctx}'..."
  until kubectl --context "${ctx}" -n istio-system get svc istio-eastwestgateway \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -Eq '[0-9]'; do
    sleep 2
  done
  kubectl --context "${ctx}" -n istio-system get svc istio-eastwestgateway
done

echo "Istio ambient multi-cluster setup complete."
