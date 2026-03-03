#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="istio-system"
CERT_NAME="istio-root-ca"
SECRET_NAME="istio-root-ca-secret"
CACERTS_SECRET="cacerts"

echo "Waiting for root CA certificate to be ready..."
kubectl wait --for=condition=Ready certificate/${CERT_NAME} -n ${NAMESPACE} --timeout=300s

echo "Extracting certificate and key from cert-manager secret..."
# Extract the certificate and key from cert-manager secret
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

echo "Creating Istio cacerts secret with proper format..."
# Delete existing cacerts secret if it exists
kubectl delete secret ${CACERTS_SECRET} -n ${NAMESPACE} --ignore-not-found=true

# Create cacerts secret with Istio's expected format
# In single-level hierarchy:
#   ca-cert.pem = root CA certificate (used to sign workload certs)
#   ca-key.pem = root CA private key
#   root-cert.pem = root CA certificate (trust anchor)
#   cert-chain.pem = certificate chain (same as root in single-level)
kubectl create secret generic ${CACERTS_SECRET} -n ${NAMESPACE} \
    --from-literal=ca-cert.pem="$ROOT_CERT" \
    --from-literal=ca-key.pem="$ROOT_KEY" \
    --from-literal=root-cert.pem="$ROOT_CERT" \
    --from-literal=cert-chain.pem="$ROOT_CERT"

echo "Istio cacerts secret created successfully!"
echo ""
echo "Verification:"
kubectl get secret ${CACERTS_SECRET} -n ${NAMESPACE} -o jsonpath='{.data}' | jq 'keys'
echo ""
echo "Certificate details:"
echo "$ROOT_CERT" | openssl x509 -noout -subject -issuer -dates
