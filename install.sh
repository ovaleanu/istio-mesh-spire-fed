#!/bin/bash
 
set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR


GATEWAY_API_VER=v1.4.1

kubectl apply --context=foo-cluster --server-side --force-conflicts -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VER}/experimental-install.yaml"

kubectl apply --context=bar-cluster --server-side --force-conflicts -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VER}/experimental-install.yaml"

kubectl create ns istio-system --context=foo-cluster
kubectl create ns istio-system --context=bar-cluster

kubectl create secret generic cacerts -n istio-system --context=foo-cluster \
  --from-file=samples/certs/ca-cert.pem \
  --from-file=samples/certs/ca-key.pem \
  --from-file=samples/certs/root-cert.pem \
  --from-file=samples/certs/cert-chain.pem

  kubectl create secret generic cacerts -n istio-system --context=bar-cluster \
  --from-file=samples/certs/ca-cert.pem \
  --from-file=samples/certs/ca-key.pem \
  --from-file=samples/certs/root-cert.pem \
  --from-file=samples/certs/cert-chain.pem

  helm upgrade --install istio-base manifests/charts/base \
  -n istio-system --kube-context foo-cluster

cat <<'EOF' | helm upgrade --install istiod manifests/charts/istio-control/istio-discovery \
  -n istio-system --kube-context foo-cluster \
  -f manifests/helm-profiles/ambient.yaml -f -
global:
  meshID: mesh1
  multiCluster:
    clusterName: foo-cluster
  network: network1
pilot:
  env:
    AMBIENT_ENABLE_MULTI_NETWORK: "true"
    ENABLE_WILDCARD_HOST_SERVICE_ENTRIES_FOR_TLS: "true"
EOF

cat <<'EOF' | helm upgrade --install istio-cni manifests/charts/istio-cni \
  -n istio-system --kube-context foo-cluster \
  -f manifests/helm-profiles/ambient.yaml -f -
global:
  meshID: mesh1
  multiCluster:
    clusterName: foo-cluster
  network: network1
EOF

cat <<'EOF' | helm upgrade --install ztunnel manifests/charts/ztunnel \
  -n istio-system --kube-context foo-cluster \
  -f manifests/helm-profiles/ambient.yaml -f -
global:
  meshID: mesh1
  multiCluster:
    clusterName: foo-cluster
  network: network1
EOF

kubectl label ns istio-system --context foo-cluster topology.istio.io/network=network1 --overwrite

helm upgrade --install istio-base manifests/charts/base \
  -n istio-system --kube-context bar-cluster

cat <<'EOF' | helm upgrade --install istiod manifests/charts/istio-control/istio-discovery \
  -n istio-system --kube-context bar-cluster \
  -f manifests/helm-profiles/ambient.yaml -f -
global:
  meshID: mesh1
  multiCluster:
    clusterName: bar-cluster
  network: network2
pilot:
  env:
    AMBIENT_ENABLE_MULTI_NETWORK: "true"
    ENABLE_WILDCARD_HOST_SERVICE_ENTRIES_FOR_TLS: "true"
EOF

cat <<'EOF' | helm upgrade --install istio-cni manifests/charts/istio-cni \
  -n istio-system --kube-context bar-cluster \
  -f manifests/helm-profiles/ambient.yaml -f -
global:
  meshID: mesh1
  multiCluster:
    clusterName: bar-cluster
  network: network2
EOF

cat <<'EOF' | helm upgrade --install ztunnel manifests/charts/ztunnel \
  -n istio-system --kube-context bar-cluster \
  -f manifests/helm-profiles/ambient.yaml -f -
global:
  meshID: mesh1
  multiCluster:
    clusterName: bar-cluster
  network: network2
EOF

kubectl label ns istio-system --context bar-cluster topology.istio.io/network=network2 --overwrite

# Handle differences between macOS and Linux base64 commands
b64dec() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

# Get IP addresses of kind control-plane nodes
SERVER_FOO_CLUSTER="https://$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' foo-cluster-control-plane):6443"
SERVER_BAR_CLUSTER="https://$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bar-cluster-control-plane):6443"

# Create service account token for foo-cluster
kubectl apply --context foo-cluster -f - <<'EOF'
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
until kubectl get --context foo-cluster -n istio-system secret istio-reader-service-account-istio-remote-secret-token \
  -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; do
  sleep 1
done

TOKEN_FOO_CLUSTER="$(kubectl get --context foo-cluster -n istio-system secret istio-reader-service-account-istio-remote-secret-token \
  -o jsonpath='{.data.token}' | b64dec)"
CA_B64_FOO_CLUSTER="$(kubectl get --context foo-cluster -n istio-system secret istio-reader-service-account-istio-remote-secret-token \
  -o jsonpath='{.data.ca\.crt}')"

# Create secret in bar-cluster to access foo-cluster
kubectl apply --context bar-cluster -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: istio-remote-secret-foo-cluster
  namespace: istio-system
  labels:
    istio/multiCluster: "true"
  annotations:
    networking.istio.io/cluster: foo-cluster
stringData:
  foo-cluster: |
    apiVersion: v1
    kind: Config
    clusters:
    - name: foo-cluster
      cluster:
        server: ${SERVER_FOO_CLUSTER}
        certificate-authority-data: ${CA_B64_FOO_CLUSTER}
    contexts:
    - name: foo-cluster
      context:
        cluster: foo-cluster
        user: foo-cluster
    current-context: foo-cluster
    users:
    - name: foo-cluster
      user:
        token: ${TOKEN_FOO_CLUSTER}
EOF

# Create service account token for bar-cluster
kubectl apply --context bar-cluster -f - <<'EOF'
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
until kubectl get --context bar-cluster -n istio-system secret istio-reader-service-account-istio-remote-secret-token \
  -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; do
  sleep 1
done

TOKEN_BAR_CLUSTER="$(kubectl get --context bar-cluster -n istio-system secret istio-reader-service-account-istio-remote-secret-token \
  -o jsonpath='{.data.token}' | b64dec)"
CA_B64_BAR_CLUSTER="$(kubectl get --context bar-cluster -n istio-system secret istio-reader-service-account-istio-remote-secret-token \
  -o jsonpath='{.data.ca\.crt}')"

# Create secret in foo-cluster to access bar-cluster
kubectl apply --context foo-cluster --server-side -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: istio-remote-secret-bar-cluster
  namespace: istio-system
  labels:
    istio/multiCluster: "true"
  annotations:
    networking.istio.io/cluster: bar-cluster
stringData:
  bar-cluster: |
    apiVersion: v1
    kind: Config
    clusters:
    - name: bar-cluster
      cluster:
        server: ${SERVER_BAR_CLUSTER}
        certificate-authority-data: ${CA_B64_BAR_CLUSTER}
    contexts:
    - name: bar-cluster
      context:
        cluster: bar-cluster
        user: bar-cluster
    current-context: bar-cluster
    users:
    - name: bar-cluster
      user:
        token: ${TOKEN_BAR_CLUSTER}
EOF


kubectl apply --context foo-cluster --server-side -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: "network1"
spec:
  gatewayClassName: "istio-east-west"
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
      tls:
        mode: Terminate
        options:
          gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
EOF

kubectl apply --context bar-cluster --server-side -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: "network2"
spec:
  gatewayClassName: "istio-east-west"
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
      tls:
        mode: Terminate
        options:
          gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
EOF

for c in foo-cluster bar-cluster; do
  echo "=== waiting EXTERNAL-IP for $c"
  until kubectl --context "$c" -n istio-system get svc istio-eastwestgateway \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -Eq '[0-9]'; do
    sleep 2
  done
  kubectl --context "$c" -n istio-system get svc istio-eastwestgateway
done

kubectl create ns sample --context foo-cluster
kubectl create ns sample --context bar-cluster

kubectl label ns sample --context foo-cluster istio.io/dataplane-mode=ambient --overwrite
kubectl label ns sample --context bar-cluster istio.io/dataplane-mode=ambient --overwrite

# Create Service in both clusters
kubectl apply --context foo-cluster -n sample -f samples/helloworld/helloworld.yaml -l service=helloworld
kubectl apply --context bar-cluster -n sample -f samples/helloworld/helloworld.yaml -l service=helloworld

# Create Deployment with different versions in each cluster
kubectl apply --context foo-cluster -n sample -f samples/helloworld/helloworld.yaml -l version=v1
kubectl apply --context bar-cluster -n sample -f samples/helloworld/helloworld.yaml -l version=v2

# Mark as global service (enable cross-cluster communication)
kubectl label svc helloworld --context foo-cluster -n sample istio.io/global=true --overwrite
kubectl label svc helloworld --context bar-cluster -n sample istio.io/global=true --overwrite

kubectl apply --context foo-cluster -n sample -f samples/curl/curl.yaml
kubectl apply --context bar-cluster -n sample -f samples/curl/curl.yaml

for i in {1..10}; do
  kubectl exec --context foo-cluster -n sample deploy/curl -c curl -- \
    curl -sS "helloworld.sample:5000/hello"
done