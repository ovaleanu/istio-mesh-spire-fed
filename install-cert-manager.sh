#/bin/bash

set -e

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster

# Install cert-manager on foo cluster
kubectl config use-context ${CTX_CLUSTER1}

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.1/cert-manager.yaml

kubectl -n cert-manager rollout status deployment/cert-manager
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector
kubectl -n cert-manager rollout status deployment/cert-manager-webhook

kubectl apply \
  -f ./cert-manager/self-signed-ca.yaml \
  -f ./cert-manager/istio-cert.yaml

# Install cert-manager on bar cluster
kubectl config use-context ${CTX_CLUSTER2}

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.1/cert-manager.yaml

kubectl -n cert-manager rollout status deployment/cert-manager
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector
kubectl -n cert-manager rollout status deployment/cert-manager-webhook

kubectl apply \
  -f ./cert-manager/self-signed-ca.yaml \
  -f ./cert-manager/istio-cert.yaml