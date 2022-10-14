#!/bin/bash

set -e

#kubectl create ns spire

# Create the k8s-workload-registrar crd, configmap and associated role bindingsspace
kubectl apply \
    -f spire-ns.yaml \
    -f k8s-workload-registrar-crd-cluster-role.yaml \
    -f k8s-workload-registrar-crd-configmap-google.yaml \
    -f spiffeid.spiffe.io_spiffeids.yaml

# Create the server’s service account, configmap and associated role bindings
kubectl apply \
    -f server-account.yaml \
    -f spire-bundle-configmap.yaml \
    -f server-cluster-role.yaml

# Deploy the server configmap and statefulset
kubectl apply \
    -f server-configmap-google.yaml \
    -f server-statefulset.yaml \
    -f server-service.yaml

# Configuring and deploying the SPIRE Agent
kubectl apply \
    -f agent-account.yaml \
    -f agent-cluster-role.yaml

sleep 2

kubectl apply \
    -f agent-configmap-google.yaml \
    -f agent-daemonset.yaml

# Applying SPIFFE CSI Driver configuration
kubectl apply -f spiffe-csi-driver.yaml
