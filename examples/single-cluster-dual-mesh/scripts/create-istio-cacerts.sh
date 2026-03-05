#!/usr/bin/env bash

set -euo pipefail

# Default to istio-system, allow override
NAMESPACE="${1:-istio-system}"
CERT_NAME="istio-root-ca"
SECRET_NAME="istio-root-ca-secret"
CACERTS_SECRET="cacerts"

echo "Creating cacerts for namespace: $NAMESPACE"

# For mesh-2 (istio-system-2), we copy the root CA from istio-system
if [ "$NAMESPACE" != "istio-system" ]; then
    echo "Creating namespace $NAMESPACE if it doesn't exist..."
    kubectl create namespace $NAMESPACE 2>/dev/null || true

    echo "Copying root CA secret from istio-system to $NAMESPACE..."
    # Copy the certificate resource to the new namespace
    kubectl get certificate ${CERT_NAME} -n istio-system -o yaml | \
        sed "s/namespace: istio-system/namespace: $NAMESPACE/" | \
        kubectl apply -f -

    # Copy the secret to the new namespace
    kubectl get secret ${SECRET_NAME} -n istio-system -o yaml | \
        sed "s/namespace: istio-system/namespace: $NAMESPACE/" | \
        kubectl apply -f -
fi

echo "Waiting for root CA certificate to be ready in $NAMESPACE..."
kubectl wait --for=condition=Ready certificate/${CERT_NAME} -n ${NAMESPACE} --timeout=300s 2>/dev/null || true

echo "Extracting certificate and key from cert-manager secret..."
ROOT_CERT=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.tls\.crt}' | base64 -d)
ROOT_KEY=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.tls\.key}' | base64 -d)

# Validate certificate files
if [ -z "$ROOT_CERT" ]; then
    echo "Error: Failed to extract root certificate"
    exit 1
fi

if [ -z "$ROOT_KEY" ]; then
    echo "Error: Failed to extract root key"
    exit 1
fi

echo "Creating Istio cacerts secret in $NAMESPACE..."
kubectl delete secret ${CACERTS_SECRET} -n ${NAMESPACE} --ignore-not-found=true

# Create cacerts secret with Istio's expected format
kubectl create secret generic ${CACERTS_SECRET} -n ${NAMESPACE} \
    --from-literal=ca-cert.pem="$ROOT_CERT" \
    --from-literal=ca-key.pem="$ROOT_KEY" \
    --from-literal=root-cert.pem="$ROOT_CERT" \
    --from-literal=cert-chain.pem="$ROOT_CERT"

echo "Istio cacerts secret created successfully in $NAMESPACE!"
echo ""
echo "Verification:"
kubectl get secret ${CACERTS_SECRET} -n ${NAMESPACE} -o jsonpath='{.data}' | jq 'keys'
echo ""
echo "Certificate details:"
echo "$ROOT_CERT" | openssl x509 -noout -subject -issuer -dates
