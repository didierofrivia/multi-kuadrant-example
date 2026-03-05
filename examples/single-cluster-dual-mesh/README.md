# Example 2: Single Cluster, Dual Mesh

This example demonstrates two independent Istio service meshes running in the same Kubernetes cluster, sharing a common root CA certificate for cross-mesh mTLS communication.

## Overview

This setup creates two completely independent Istio control planes (mesh-1 and mesh-2) in the same cluster. Each mesh has:
- Its own namespace (`istio-system` and `istio-system-2`)
- Its own Istiod control plane
- Its own trust domain
- Its own set of workload namespaces

Despite being independent, both meshes share the same root CA certificate, which enables secure mTLS communication between services across mesh boundaries.

## Architecture

```
Cluster-A (kind)
├── Shared Infrastructure
│   ├── cert-manager (manages shared root CA)
│   ├── MetalLB (load balancer)
│   └── istio-cni (shared CNI)
│
├── Mesh-1
│   ├── istio-system (namespace)
│   │   ├── istiod (control plane)
│   │   ├── cacerts (from shared root CA)
│   │   └── PeerAuthentication (mTLS mode: PERMISSIVE)
│   ├── mesh-demo-apps (namespace)
│   │   └── echo-api (with sidecar, mesh=mesh-1)
│   └── mesh-client-apps (namespace)
│       └── curl-client (with sidecar, mesh=mesh-1)
│
└── Mesh-2
    ├── istio-system-2 (namespace)
    │   ├── istiod (control plane)
    │   ├── cacerts (from shared root CA)
    │   └── PeerAuthentication (mTLS mode: PERMISSIVE)
    ├── mesh-demo-apps-2 (namespace)
    │   └── echo-api-2 (with sidecar, mesh=mesh-2)
    └── mesh-client-apps-2 (namespace)
        └── curl-client (with sidecar, mesh=mesh-2)
```

## Key Features

### Mesh Isolation
- **Separate Control Planes**: Each mesh has its own Istiod instance
- **Independent Discovery**: Meshes use discovery selectors (`mesh=mesh-1`, `mesh=mesh-2`)
- **Network Separation**: Different network IDs (`network-1`, `network-2`)
- **Distinct Trust Domains**:
  - Mesh-1: `mesh-1.10.89.0.0.nip.io`
  - Mesh-2: `mesh-2.10.89.0.0.nip.io`

### Shared CA for Cross-Mesh mTLS
- **Single Root CA**: One root certificate managed by cert-manager
- **Distributed to Both Meshes**: Same CA certificate copied to both namespaces
- **Cross-Mesh Trust**: Workloads from different meshes can establish mTLS
- **Certificate Validation**: Each Istiod validates certificates against the shared root CA

### How Cross-Mesh mTLS Works

1. **Shared Root CA**: cert-manager creates a single root CA in `istio-system`
2. **CA Distribution**: The root CA is copied to `istio-system-2`
3. **Workload Certificates**: Each Istiod signs certificates with its trust domain
4. **mTLS Handshake**: When mesh-1 client calls mesh-2 service:
   - Client presents certificate signed by mesh-1's Istiod
   - Server presents certificate signed by mesh-2's Istiod
   - Both validate against the shared root CA
   - Secure connection established

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- kubectl
- helm
- jq
- yq

## Quick Start

### From Repository Root

```bash
make example-2
```

### From This Directory

```bash
make setup
```

## Installation Steps Explained

The installation process:

1. **Install Dependencies**
   - Gateway API CRDs
   - MetalLB for load balancing
   - cert-manager for certificate management
   - Istio CNI (shared by both meshes)

2. **Install Mesh-1**
   - Create `istio-system` namespace
   - Generate root CA certificate
   - Install Sail Operator
   - Deploy Istio control plane for mesh-1
   - Enable mTLS (PERMISSIVE mode)

3. **Install Mesh-2**
   - Create `istio-system-2` namespace
   - Copy root CA from mesh-1
   - Deploy Istio control plane for mesh-2
   - Enable mTLS (PERMISSIVE mode)

4. **Deploy Applications**
   - Deploy echo-api and curl-client in mesh-1 namespaces
   - Deploy echo-api-2 and curl-client in mesh-2 namespaces

## Testing

### Test Intra-Mesh Communication

Test that mTLS works within each mesh:

```bash
make test-mtls
```

Expected output shows certificates for both meshes:
```
=== Mesh-1 mTLS Test ===
"By=spiffe://mesh-1.10.89.0.0.nip.io/ns/mesh-demo-apps/sa/default;..."

=== Mesh-2 mTLS Test ===
"By=spiffe://mesh-2.10.89.0.0.nip.io/ns/mesh-demo-apps-2/sa/default;..."
```

### Test Cross-Mesh Communication

Test communication between services in different meshes:

```bash
make test-cross-mesh
```

This runs 4 tests:

1. **Mesh-1 → Mesh-1**: Intra-mesh communication (should show mesh-1 certs)
2. **Mesh-2 → Mesh-2**: Intra-mesh communication (should show mesh-2 certs)
3. **Mesh-1 → Mesh-2**: Cross-mesh communication (should show mTLS with mixed trust domains)
4. **Mesh-2 → Mesh-1**: Cross-mesh communication (should show mTLS with mixed trust domains)

### Expected Results

All 4 tests should succeed with mTLS certificates present in the `HTTP_X_FORWARDED_CLIENT_CERT` header, demonstrating:
- ✅ Intra-mesh mTLS works in both meshes
- ✅ Cross-mesh mTLS works in both directions
- ✅ Shared root CA enables trust across mesh boundaries

## Components

### Istio
- **Version**: v1.27.1
- **Operator**: Sail Operator v1.28.3
- **Control Planes**: 2 (one per mesh)
- **CNI**: Shared across both meshes

### Certificates
- **Manager**: cert-manager v1.15.3
- **Root CA**: Single self-signed certificate
- **Lifetime**: 10 years
- **Distribution**: Copied to both mesh namespaces

### Trust Domains
- **Mesh-1**: `mesh-1.10.89.0.0.nip.io`
- **Mesh-2**: `mesh-2.10.89.0.0.nip.io`

### Networks
- **Mesh-1**: `network-1`
- **Mesh-2**: `network-2`

## Configuration Details

### Mesh-1 Configuration

**Namespace**: `istio-system`

**Discovery Selector**:
```yaml
discoverySelectors:
  - matchLabels:
      istio-discovery: enabled
      mesh: mesh-1
```

**Workload Namespaces**:
- `mesh-demo-apps` (echo-api)
- `mesh-client-apps` (curl-client)

### Mesh-2 Configuration

**Namespace**: `istio-system-2`

**Discovery Selector**:
```yaml
discoverySelectors:
  - matchLabels:
      istio-discovery: enabled
      mesh: mesh-2
```

**Workload Namespaces**:
- `mesh-demo-apps-2` (echo-api-2)
- `mesh-client-apps-2` (curl-client)

## Manual Testing

### Verify Both Control Planes Running

```bash
# Check mesh-1 control plane
kubectl get pods -n istio-system

# Check mesh-2 control plane
kubectl get pods -n istio-system-2
```

### Verify Shared Root CA

```bash
# Check root CA in mesh-1
kubectl get secret cacerts -n istio-system -o jsonpath='{.data.root-cert\.pem}' | base64 -d | openssl x509 -noout -subject

# Check root CA in mesh-2
kubectl get secret cacerts -n istio-system-2 -o jsonpath='{.data.root-cert\.pem}' | base64 -d | openssl x509 -noout -subject

# They should have the same subject (shared root CA)
```

### Test Communication Manually

```bash
# Test mesh-1 → mesh-1
kubectl exec -n mesh-client-apps deploy/curl-client -- \
  curl -s http://echo-api.mesh-demo-apps.svc.cluster.local:3000/echo | jq

# Test mesh-2 → mesh-2
kubectl exec -n mesh-client-apps-2 deploy/curl-client -- \
  curl -s http://echo-api-2.mesh-demo-apps-2.svc.cluster.local:3000/echo | jq

# Test mesh-1 → mesh-2 (cross-mesh)
kubectl exec -n mesh-client-apps deploy/curl-client -- \
  curl -s http://echo-api-2.mesh-demo-apps-2.svc.cluster.local:3000/echo | jq

# Test mesh-2 → mesh-1 (cross-mesh)
kubectl exec -n mesh-client-apps-2 deploy/curl-client -- \
  curl -s http://echo-api.mesh-demo-apps.svc.cluster.local:3000/echo | jq
```

### Verify mTLS Certificates

```bash
# Check mesh-1 workload certificate
kubectl exec -n mesh-demo-apps deploy/echo-api -c istio-proxy -- \
  openssl s_client -connect localhost:15000 -showcerts 2>/dev/null | \
  openssl x509 -noout -text | grep -A1 "Subject Alternative Name"

# Check mesh-2 workload certificate
kubectl exec -n mesh-demo-apps-2 deploy/echo-api-2 -c istio-proxy -- \
  openssl s_client -connect localhost:15000 -showcerts 2>/dev/null | \
  openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
```

## Troubleshooting

### Mesh-2 Control Plane Not Starting

Check the Istio CR status:
```bash
kubectl get istio -n istio-system-2 default-2 -o yaml
```

Verify cacerts secret exists:
```bash
kubectl get secret cacerts -n istio-system-2
```

### Cross-Mesh Communication Failing

Verify shared root CA:
```bash
# Compare root certificates - they should be identical
diff \
  <(kubectl get secret cacerts -n istio-system -o jsonpath='{.data.root-cert\.pem}') \
  <(kubectl get secret cacerts -n istio-system-2 -o jsonpath='{.data.root-cert\.pem}')
```

Check service endpoints:
```bash
# Verify services are discoverable
kubectl get endpoints -n mesh-demo-apps echo-api
kubectl get endpoints -n mesh-demo-apps-2 echo-api-2
```

### Workloads Not Joining Correct Mesh

Verify namespace labels:
```bash
# Mesh-1 workload namespaces should have: mesh=mesh-1
kubectl get namespace mesh-demo-apps -o yaml | grep -A5 labels

# Mesh-2 workload namespaces should have: mesh=mesh-2
kubectl get namespace mesh-demo-apps-2 -o yaml | grep -A5 labels
```

Verify sidecar injection:
```bash
# Check mesh-1 pod
kubectl get pod -n mesh-demo-apps -l app=echo-api -o jsonpath='{.items[0].spec.containers[*].name}'
# Should show: echo-api istio-proxy

# Check mesh-2 pod
kubectl get pod -n mesh-demo-apps-2 -l app=echo-api-2 -o jsonpath='{.items[0].spec.containers[*].name}'
# Should show: echo-api istio-proxy
```

## Cleanup

From repository root:
```bash
make clean
```

This deletes the kind cluster and all resources.

## References

- [Istio Multi-Mesh Documentation](https://istio.io/latest/docs/setup/install/multiple-controlplanes/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Sail Operator Documentation](https://github.com/istio-ecosystem/sail-operator)
