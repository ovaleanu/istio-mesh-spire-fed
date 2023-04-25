#/bin/bash

set -e

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster

kubectl config use-context $CTX_CLUSTER1
(cd istio ; ./deploy-istio-foo.sh)

kubectl config use-context $CTX_CLUSTER2
(cd istio ; ./deploy-istio-bar.sh)

istioctl x create-remote-secret --context="${CTX_CLUSTER1}" --name=foo-cluster --server=https://foo-cluster-control-plane:6443 | kubectl apply -f - --context="${CTX_CLUSTER2}"

istioctl x create-remote-secret --context="${CTX_CLUSTER2}" --name=bar-cluster --server=https://bar-cluster-control-plane:6443 | kubectl apply -f - --context="${CTX_CLUSTER1}"
