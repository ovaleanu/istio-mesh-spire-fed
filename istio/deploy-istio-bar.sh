#/bin/bash

istioctl install -f istio-conf-new-bar.yaml --skip-confirmation
kubectl apply -f auth.yaml
kubectl apply -f istio-ew-gw.yaml
