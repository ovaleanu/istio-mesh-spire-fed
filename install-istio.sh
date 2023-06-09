#/bin/bash

set -e


export CTX_CLUSTER1=foo-cluster
export CTX_CLUSTER2=bar-cluster

kubectl config use-context $CTX_CLUSTER1

istioctl install -f ./istio/istio-conf-foo.yaml --skip-confirmation
kubectl apply -f ./istio/auth.yaml
kubectl apply -f ./istio/istio-ew-gw.yaml

kubectl config use-context $CTX_CLUSTER2

istioctl install -f ./istio/istio-conf-bar.yaml --skip-confirmation
kubectl apply -f ./istio/auth.yaml
kubectl apply -f ./istio/istio-ew-gw.yaml

istioctl x create-remote-secret --context="${CTX_CLUSTER1}" --name=foo-cluster --server=https://foo-cluster-control-plane:6443 | kubectl apply -f - --context="${CTX_CLUSTER2}"

istioctl x create-remote-secret --context="${CTX_CLUSTER2}" --name=bar-cluster --server=https://bar-cluster-control-plane:6443 | kubectl apply -f - --context="${CTX_CLUSTER1}"
