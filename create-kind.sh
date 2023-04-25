#!/bin/bash

set -e

# create kind cluster foo
kind create cluster --config=kind/kind-foo.yaml

# create kind cluster bar
kind create cluster --config=kind/kind-bar.yaml

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster

# install LB for the east west gw
kubectl apply -f kind/metallb.yaml --context=$CTX_CLUSTER1
kubectl apply -f kind/metallb.yaml --context=$CTX_CLUSTER2

#IP range addresses for MetalLB
docker network inspect -f '{{.IPAM.Config}}' kind

kubectl apply -f kind/metallb-cm-foo.yaml --context $CTX_CLUSTER1
kubectl apply -f kind/metallb-cm-bar.yaml --context $CTX_CLUSTER2
