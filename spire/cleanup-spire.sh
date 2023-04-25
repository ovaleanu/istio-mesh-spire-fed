#!/bin/bash
set -e

export CTX_CLUSTER1=kind-foo-cluster
export CTX_CLUSTER2=kind-bar-cluster

kubectl config use-context ${CTX_CLUSTER1}

kubectl delete CustomResourceDefinition spiffeids.spiffeid.spiffe.io
kubectl delete -f k8s-workload-registrar-crd-configmap-foo.yaml 
kubectl delete -f k8s-workload-registrar-crd-cluster-role.yaml  
kubectl delete clusterrole spire-server-trust-role spire-agent-cluster-role
kubectl delete clusterrolebinding spire-server-trust-role-binding spire-agent-cluster-role-binding
kubectl delete namespace spire

kubectl config use-context ${CTX_CLUSTER2}

kubectl delete CustomResourceDefinition spiffeids.spiffeid.spiffe.io
kubectl delete -f k8s-workload-registrar-crd-configmap-bar.yaml 
kubectl delete -f k8s-workload-registrar-crd-cluster-role.yaml  
kubectl delete clusterrole spire-server-trust-role spire-agent-cluster-role
kubectl delete clusterrolebinding spire-server-trust-role-binding spire-agent-cluster-role-binding
kubectl delete namespace spire
