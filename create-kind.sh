#!/bin/bash

set -e
# create kind cluster foo
kind create cluster --config=kind/kind-foo.yaml

# create kind cluster bar
kind create cluster --config=kind/kind-bar.yaml

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster

# install LB for the east west gw
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml --context=$CTX_CLUSTER1
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s \
                --context=$CTX_CLUSTER1

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml --context=$CTX_CLUSTER2
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s \
                --context=$CTX_CLUSTER2

#IP range addresses for MetalLB
docker network inspect -f '{{.IPAM.Config}}' kind

kubectl apply -f kind/metallb-foo.yaml --context=$CTX_CLUSTER1
kubectl apply -f kind/metallb-bar.yaml --context=$CTX_CLUSTER2
