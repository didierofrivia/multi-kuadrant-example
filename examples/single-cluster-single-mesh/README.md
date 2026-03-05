# Example 1: Single Cluster, Single Mesh with Custom Certificates

This example demonstrates a complete Istio service mesh setup with custom CA certificates managed by cert-manager.

## Features

- Single Kubernetes cluster (kind)
- Single Istio service mesh
- Custom CA certificates via cert-manager
- mTLS communication between workloads
- Kuadrant integration
- MetalLB for load balancer support

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- kubectl
- helm
- jq
- yq

## Quick Start

### From Repository Root

```bash
make setup-example-1
```

### From This Directory

```bash
make setup
```

## Architecture

```
Cluster-A
├── istio-system (control plane)
│   ├── istiod
│   ├── cert-manager (custom CA)
│   └── cacerts secret (10-year root CA)
├── istio-cni
├── mesh-demo-apps
│   └── echo-api (with sidecar)
├── mesh-client-apps
│   └── curl-client (with sidecar)
└── no-mesh-client-apps
    └── curl-client (no sidecar)
```

## Components

- **Istio**: v1.27.1 (via Sail Operator v1.28.3)
- **cert-manager**: v1.15.3
- **Kuadrant**: Latest from helm repo
- **MetalLB**: For load balancer support in kind
- **Gateway API**: v1.4.0

## Certificate Details

### Root CA Configuration

- **Lifetime**: 10 years (87600 hours)
- **Issuer**: Self-signed ClusterIssuer
- **Trust Domain**: `10.89.0.0.nip.io`
- **Management**: cert-manager

### Certificate Hierarchy

```
selfsigned-issuer (ClusterIssuer)
└── istio-root-ca (Certificate)
    └── istio-root-ca-secret (Secret)
        └── cacerts (Istio secret)
            ├── ca-cert.pem
            ├── ca-key.pem
            ├── root-cert.pem
            └── cert-chain.pem
```

## Testing

### Test mTLS Communication

```bash
make test-mtls
```

This runs two tests:
1. **Within mesh**: curl-client (with sidecar) → echo-api
   - Should show `X-Forwarded-Client-Cert` header (mTLS enabled)
2. **Outside mesh**: curl-client (no sidecar) → echo-api
   - Should show `null` (no client certificate)

### Expected Output

```
Current mTLS mode:
PERMISSIVE

=== Test 1: Client within mesh → echo-api ===
"By=spiffe://10.89.0.0.nip.io/ns/mesh-demo-apps/sa/default;Hash=<redacted>;Subject=\"\";URI=spiffe://10.89.0.0.nip.io/ns/mesh-client-apps/sa/default"

=== Test 2: Client outside mesh → echo-api ===
null
```

### Change mTLS Mode

Switch to STRICT mode (reject non-mTLS connections):
```bash
make mtls-mode-strict
```

Switch back to PERMISSIVE mode:
```bash
make mtls-mode-permissive
```

## Manual Testing

### Test from within mesh
```bash
kubectl exec -n mesh-client-apps deploy/curl-client -- \
  curl -s http://echo-api.mesh-demo-apps.svc.cluster.local:3000/echo | jq
```

### Test from outside mesh
```bash
kubectl exec -n no-mesh-client-apps deploy/curl-client -- \
  curl -s http://echo-api.mesh-demo-apps.svc.cluster.local:3000/echo | jq
```

### Verify Certificate Chain
```bash
# Check root CA certificate
kubectl get certificate -n istio-system istio-root-ca -o yaml

# Check cacerts secret
kubectl get secret -n istio-system cacerts -o jsonpath='{.data}' | jq 'keys'

# Verify certificate details
kubectl get secret -n istio-system istio-root-ca-secret -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -text
```

## Cleanup

From repository root:
```bash
make clean
```

This deletes the kind cluster and all resources.
