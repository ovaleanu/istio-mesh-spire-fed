#/bin/bash

export CTX_CLUSTER1=foo-cluster
export CTX_CLUSTER2=bar-cluster

echo ">>> curl hellowold end point to see if they are up"
sleep 2

kubectl exec --context="${CTX_CLUSTER1}" -n sleep -c sleep \
    "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sleep -l \
    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.helloworld:5000/hello
sleep 4

kubectl exec --context="${CTX_CLUSTER2}" -n sleep -c sleep \
    "$(kubectl get pod --context="${CTX_CLUSTER2}" -n sleep -l \
    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.helloworld:5000/hello
sleep 3

echo " >>> All the pods are running and accessible, scalling the local helloworld-v1 to 0, so that the curl command can reach the other pod in the other cluster"

kubectl -n helloworld scale deploy helloworld-v1 --context="${CTX_CLUSTER1}" --replicas 0
sleep 4

echo ">>> curling helloworld, it should reach the other cluster"

kubectl exec --context="${CTX_CLUSTER1}" -n sleep -c sleep \
    "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sleep -l \
    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.helloworld:5000/hello