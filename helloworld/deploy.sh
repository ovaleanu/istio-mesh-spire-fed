#!/bin/bash

set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CTX_CLUSTER1="foo-cluster"
CTX_CLUSTER2="bar-cluster"
ROLLOUT_TIMEOUT="120s"

# Create namespaces
kubectl create --context="${CTX_CLUSTER1}" namespace sleep --dry-run=client -o yaml | kubectl apply --context="${CTX_CLUSTER1}" -f -
kubectl create --context="${CTX_CLUSTER1}" namespace helloworld --dry-run=client -o yaml | kubectl apply --context="${CTX_CLUSTER1}" -f -
kubectl create --context="${CTX_CLUSTER2}" namespace sleep --dry-run=client -o yaml | kubectl apply --context="${CTX_CLUSTER2}" -f -
kubectl create --context="${CTX_CLUSTER2}" namespace helloworld --dry-run=client -o yaml | kubectl apply --context="${CTX_CLUSTER2}" -f -

# Label namespaces for ambient mode
kubectl label --context="${CTX_CLUSTER1}" namespace sleep \
    istio.io/dataplane-mode=ambient --overwrite
kubectl label --context="${CTX_CLUSTER1}" namespace helloworld \
    istio.io/dataplane-mode=ambient --overwrite

kubectl label --context="${CTX_CLUSTER2}" namespace sleep \
    istio.io/dataplane-mode=ambient --overwrite
kubectl label --context="${CTX_CLUSTER2}" namespace helloworld \
    istio.io/dataplane-mode=ambient --overwrite

# Deploy helloworld (Service + ServiceAccount + Deployment)
kubectl apply --context="${CTX_CLUSTER1}" \
    -f "${SCRIPT_DIR}/helloworld-foo.yaml" -n helloworld

kubectl -n helloworld --context="${CTX_CLUSTER1}" rollout status deploy helloworld-v1 --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n helloworld get pod --context="${CTX_CLUSTER1}" -l app=helloworld

kubectl apply --context="${CTX_CLUSTER2}" \
    -f "${SCRIPT_DIR}/helloworld-bar.yaml" -n helloworld


kubectl -n helloworld --context="${CTX_CLUSTER2}" rollout status deploy helloworld-v2 --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n helloworld get pod --context="${CTX_CLUSTER2}" -l app=helloworld

# Deploy sleep clients
kubectl apply --context="${CTX_CLUSTER1}" \
    -f "${SCRIPT_DIR}/sleep-foo.yaml" -n sleep
kubectl apply --context="${CTX_CLUSTER2}" \
    -f "${SCRIPT_DIR}/sleep-bar.yaml" -n sleep

kubectl -n sleep --context="${CTX_CLUSTER1}" rollout status deploy sleep --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n sleep get pod --context="${CTX_CLUSTER1}" -l app=sleep

kubectl -n sleep --context="${CTX_CLUSTER2}" rollout status deploy sleep --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n sleep get pod --context="${CTX_CLUSTER2}" -l app=sleep
