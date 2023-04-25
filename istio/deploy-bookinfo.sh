#/bin/bash

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster


kubectl config use-context ${CTX_CLUSTER1}

istioctl kube-inject -f bookinfo-with-spire-template.yaml | kubectl apply -f -
sleep 6

echo " >>>Check whether SPIRE has issued an identity to the workload"

kubectl exec -i -t spire-server-0 -n spire -c spire-server -- /bin/sh -c "bin/spire-server entry show -socketPath /run/spire/sockets/server.sock"