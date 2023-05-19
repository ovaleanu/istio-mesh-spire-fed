#/bin/bash

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster

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

#sleep 2

#echo ""
#echo "configuring auth policy"
#echo ""

#kubectl apply --context="${CTX_CLUSTER1}" \
#    -f helloworld/auth-policy-foo.yaml -n helloworld
#kubectl apply --context="${CTX_CLUSTER2}" \
#    -f helloworld/auth-policy-bar.yaml -n helloworld

#sleep 2

#echo ""
#echo "curl the helloworld@bar from sleep@foo"
#echo ""


#kubectl exec --context="${CTX_CLUSTER1}" -n sleep -c sleep \
#    "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sleep -l \
#    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
#    -- curl -sS helloworld.helloworld:5000/hello

#echo ""
#echo ""
#echo ">>> run the below command to test it manually"
#echo ""

#echo "
#kubectl exec --context="${CTX_CLUSTER1}" -n sleep -c sleep \
#    "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sleep -l \
#    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
#    -- curl -sS helloworld.helloworld:5000/hello
#"
