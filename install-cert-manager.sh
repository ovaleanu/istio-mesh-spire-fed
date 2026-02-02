#!/bin/bash

set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

# --- Configuration ---
CERT_MANAGER_VERSION="v1.19.2"
CERT_MANAGER_MANIFEST="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
ROLLOUT_TIMEOUT="120s"

CTX_CLUSTER1="foo-cluster"
CTX_CLUSTER2="bar-cluster"

# --- Functions ---

install_cert_manager() {
  local ctx=$1

  echo "Installing cert-manager ${CERT_MANAGER_VERSION} on context '${ctx}'..."

  kubectl apply -f "${CERT_MANAGER_MANIFEST}" --context="${ctx}"

  kubectl -n cert-manager rollout status deployment/cert-manager --timeout="${ROLLOUT_TIMEOUT}" --context="${ctx}"
  kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout="${ROLLOUT_TIMEOUT}" --context="${ctx}"
  kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout="${ROLLOUT_TIMEOUT}" --context="${ctx}"

  echo "cert-manager installed successfully on '${ctx}'."
}

wait_for_secret() {
  local ctx=$1 namespace=$2 secret=$3
  local retries=30

  echo "Waiting for secret '${secret}' in namespace '${namespace}' on '${ctx}'..."
  for i in $(seq 1 "${retries}"); do
    if kubectl get secret "${secret}" -n "${namespace}" --context="${ctx}" &>/dev/null; then
      echo "Secret '${secret}' is ready."
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Timed out waiting for secret '${secret}'." >&2
  return 1
}

create_istio_cacerts() {
  local ctx=$1

  echo "Creating Istio cacerts secret (generic format) on '${ctx}'..."

  # Extract certs from the cert-manager TLS secret
  local ca_cert ca_key root_cert
  ca_cert=$(kubectl get secret cacerts-cm -n istio-system --context="${ctx}" -o jsonpath='{.data.tls\.crt}' | base64 -d)
  ca_key=$(kubectl get secret cacerts-cm -n istio-system --context="${ctx}" -o jsonpath='{.data.tls\.key}' | base64 -d)
  root_cert=$(kubectl get secret cacerts-cm -n istio-system --context="${ctx}" -o jsonpath='{.data.ca\.crt}' | base64 -d)

  # cert-chain.pem = intermediate cert + root cert
  local cert_chain="${ca_cert}
${root_cert}"

  # Create the generic secret with Istio's expected key names
  kubectl create secret generic cacerts -n istio-system --context="${ctx}" \
    --from-literal=ca-cert.pem="${ca_cert}" \
    --from-literal=ca-key.pem="${ca_key}" \
    --from-literal=root-cert.pem="${root_cert}" \
    --from-literal=cert-chain.pem="${cert_chain}" \
    --dry-run=client -o yaml | kubectl apply --context="${ctx}" -f -

  echo "Istio cacerts secret ready on '${ctx}'."
}

# --- Main ---

# 1. Install cert-manager on both clusters
install_cert_manager "${CTX_CLUSTER1}"
install_cert_manager "${CTX_CLUSTER2}"

# 2. On foo-cluster: generate the root CA (Issuer + Certificate + ClusterIssuer)
echo "Setting up root CA on '${CTX_CLUSTER1}'..."
kubectl apply -f ./cert-manager/self-signed-ca.yaml --context="${CTX_CLUSTER1}"
wait_for_secret "${CTX_CLUSTER1}" "cert-manager" "selfsigned-ca"

# 3. Export root CA secret from foo-cluster and import to bar-cluster
echo "Copying root CA secret from '${CTX_CLUSTER1}' to '${CTX_CLUSTER2}'..."
kubectl get secret selfsigned-ca -n cert-manager --context="${CTX_CLUSTER1}" -o yaml \
  | kubectl apply --context="${CTX_CLUSTER2}" -f -

# 4. On bar-cluster: apply only the ClusterIssuer (NOT the Certificate that would regenerate the CA)
echo "Setting up ClusterIssuer on '${CTX_CLUSTER2}' using shared root CA..."
kubectl apply --context="${CTX_CLUSTER2}" -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-ca
spec:
  ca:
    secretName: selfsigned-ca
EOF

# 5. Issue Istio intermediate CA certificates on both clusters (signed by the shared root)
echo "Issuing Istio intermediate CA certificates..."
kubectl apply -f ./cert-manager/istio-cert.yaml --context="${CTX_CLUSTER1}"
kubectl apply -f ./cert-manager/istio-cert.yaml --context="${CTX_CLUSTER2}"

wait_for_secret "${CTX_CLUSTER1}" "istio-system" "cacerts-cm"
wait_for_secret "${CTX_CLUSTER2}" "istio-system" "cacerts-cm"

# 6. Transform cert-manager TLS secrets into Istio's expected generic secret format
create_istio_cacerts "${CTX_CLUSTER1}"
create_istio_cacerts "${CTX_CLUSTER2}"

echo "cert-manager setup complete. Both clusters share the same root CA."
