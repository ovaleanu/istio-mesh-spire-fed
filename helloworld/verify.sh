#!/bin/bash

set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

CTX_CLUSTER1="foo-cluster"
CTX_CLUSTER2="bar-cluster"
CURLS=10

get_sleep_pod() {
  local ctx=$1
  kubectl get pod --context="${ctx}" -n sleep -l app=sleep -o jsonpath='{.items[0].metadata.name}'
}

echo ">>> Curling helloworld from foo-cluster (should hit local v1)..."
for i in $(seq 1 "${CURLS}"); do
  kubectl exec --context="${CTX_CLUSTER1}" -n sleep \
      "$(get_sleep_pod "${CTX_CLUSTER1}")" \
      -- curl -sS helloworld.helloworld:5000/hello
done

echo ">>> Curling helloworld from bar-cluster (should hit local v2)..."
for i in $(seq 1 "${CURLS}"); do
  kubectl exec --context="${CTX_CLUSTER2}" -n sleep \
      "$(get_sleep_pod "${CTX_CLUSTER2}")" \
      -- curl -sS helloworld.helloworld:5000/hello
done

echo ">>> Scaling helloworld-v1 to 0 on foo-cluster to test cross-cluster routing..."
kubectl -n helloworld scale deploy helloworld-v1 --context="${CTX_CLUSTER1}" --replicas=0
kubectl -n helloworld rollout status deploy helloworld-v1 --context="${CTX_CLUSTER1}" --timeout=60s

echo ">>> Curling helloworld from foo-cluster (should reach v2 on bar-cluster)..."
for i in $(seq 1 "${CURLS}"); do
  kubectl exec --context="${CTX_CLUSTER1}" -n sleep \
      "$(get_sleep_pod "${CTX_CLUSTER1}")" \
      -- curl -sS helloworld.helloworld:5000/hello
done

echo ">>> Restoring helloworld-v1 to 1 replica..."
kubectl -n helloworld scale deploy helloworld-v1 --context="${CTX_CLUSTER1}" --replicas=1
kubectl -n helloworld rollout status deploy helloworld-v1 --context="${CTX_CLUSTER1}" --timeout=120s

echo ">>> Verification complete."
