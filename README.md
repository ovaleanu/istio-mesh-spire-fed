# README

## Steps

### Create clusters

`./create-kind.sh`

### Install Cert-manager on the clusters

`./install-cert-manager.sh`

### Install Spire on the clusters with federation

`./install-spire.sh`

### Install Istio on the clusters

`istioctl` needs to be in the PATH

`./install-istio.sh`

### Deploy bookinfo app

`./istio/deploy-bookinfo.sh`

### View the certificate trust chain for the productpage pod

`istioctl proxy-config secret deployment/productpage-v1 -o json | jq -r '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' | base64 --decode > chain.pem`

Open the `chain.pem` file with a text editor, and you will see two certificates. Save the two certificates in separate files and use the openssl command `openssl x509 -noout -text -in $FILE` to parse the certificate contents.

### Setting up Automatic Certificate Rotation

Modify the rotation period for istiod certificates from 60 days (1440 hours) to 30 days (720 hours), run the following command:

`kubectl -f ./cert-manager/cert-rotation.yaml --context $CTX_CLUSTER1`

Check `istiod` logs

`kubectl logs -l app=istiod -n istio-system -f`
