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

```mermaid
graph TB
    subgraph Cluster["Kubernetes Cluster (kind-cluster-a)"]
        subgraph NS_MetalLB["metallb-system namespace"]
            MetalLB[MetalLB Load Balancer]
        end

        subgraph NS_CertManager["cert-manager namespace"]
            CertManager[cert-manager]
            RootCACert[Certificate<br/>istio-root-ca]
            SelfSignedIssuer[ClusterIssuer<br/>selfsigned-issuer]
            IngressIssuer[ClusterIssuer<br/>ingress-selfsigned-issuer]
        end

        subgraph NS_Istio["istio-system namespace"]
            SailOperator[Sail Operator]
            Istiod[Istiod Control Plane]
            PeerAuth[PeerAuthentication<br/>mode: PERMISSIVE/STRICT]
            CacertsSecret[Secret<br/>cacerts]
        end

        subgraph NS_CNI["istio-cni namespace"]
            IstioCNI[Istio CNI]
        end

        subgraph NS_Kuadrant["kuadrant-system namespace"]
            KuadrantOp[Kuadrant Operator]
            KuadrantCR[Kuadrant CR<br/>mtls: enabled]
            Authorino[Authorino]
            Limitador[Limitador]
            APIKeySecret[Secret<br/>api-key-1]
        end

        subgraph NS_Gateway["ingress-gateways namespace"]
            GW[Gateway<br/>kuadrant-ingressgateway<br/>HTTP: 80, HTTPS: 443]
            TLSPolicy[TLSPolicy<br/>gateway-tls-policy]
        end

        subgraph NS_MeshApps["mesh-demo-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
            HTTPRoute[HTTPRoute<br/>echo-route<br/>path: /echo]
            AuthPolicy[AuthPolicy<br/>API Key Auth]
            RateLimitPolicy[RateLimitPolicy<br/>5 req/10s]
            EchoSvc[Service<br/>echo-api<br/>port: 3000]
            EchoDep[Deployment<br/>echo-api<br/>+ Envoy Sidecar]
        end

        subgraph NS_MeshClient["mesh-client-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
            CurlMeshDep[Deployment<br/>curl-client<br/>+ Envoy Sidecar]
        end

        subgraph NS_NoMeshClient["no-mesh-client-apps namespace"]
            CurlNoMeshDep[Deployment<br/>curl-client<br/>no sidecar]
        end
    end

    %% External traffic flow
    External[External Traffic<br/>HTTPS] --> MetalLB
    MetalLB --> GW

    %% Policy enforcement
    GW -.enforces.-> TLSPolicy
    TLSPolicy -.uses issuer.-> IngressIssuer

    GW -.routes to.-> HTTPRoute
    HTTPRoute -.enforces.-> AuthPolicy
    HTTPRoute -.enforces.-> RateLimitPolicy
    HTTPRoute -.backend.-> EchoSvc
    EchoSvc --> EchoDep

    %% Internal mesh traffic
    CurlMeshDep -.mTLS.-> EchoSvc
    CurlNoMeshDep -.plain HTTP.-> EchoSvc

    %% Certificate management - Mesh certs
    CertManager -.manages.-> SelfSignedIssuer
    SelfSignedIssuer -.signs.-> RootCACert
    RootCACert -.provides.-> CacertsSecret
    CacertsSecret -.used by.-> Istiod
    Istiod -.issues workload certs.-> EchoDep
    Istiod -.issues workload certs.-> CurlMeshDep

    %% Certificate management - Gateway certs
    CertManager -.manages.-> IngressIssuer
    IngressIssuer -.used by.-> TLSPolicy

    %% Kuadrant components
    KuadrantOp -.deploys.-> Authorino
    KuadrantOp -.deploys.-> Limitador
    AuthPolicy -.validated by.-> Authorino
    Authorino -.uses.-> APIKeySecret
    RateLimitPolicy -.enforced by.-> Limitador

    %% Istio management
    Istiod -.injects.-> EchoDep
    Istiod -.injects.-> CurlMeshDep
    PeerAuth -.enforces mTLS.-> Istiod

    %% Styling
    style NS_MeshApps fill:#e1f5ff
    style NS_MeshClient fill:#e1ffe1
    style NS_NoMeshClient fill:#ffe1e1
    style NS_Gateway fill:#fff4e1
    style NS_Kuadrant fill:#ffe1f5
    style NS_Istio fill:#f5e1ff
    style NS_CertManager fill:#fff0e6
    style NS_MetalLB fill:#f0f0f0
    style NS_CNI fill:#f5f5f5

    style GW fill:#ffd700
    style HTTPRoute fill:#90ee90
    style EchoDep fill:#87ceeb
    style CurlMeshDep fill:#98fb98
    style CurlNoMeshDep fill:#ffb6c1
    style PeerAuth fill:#dda0dd
    style RootCACert fill:#ffa07a
    style CacertsSecret fill:#ff8c42
    style CertManager fill:#ff7f50

    style TLSPolicy fill:#ffd700
    style AuthPolicy fill:#ffb347
    style RateLimitPolicy fill:#ffb347
    style Authorino fill:#da70d6
    style Limitador fill:#da70d6
    style SelfSignedIssuer fill:#ffa07a
    style IngressIssuer fill:#ffa07a
```

## Components

### Core Infrastructure
- **Istio**: v1.27.1 (via Sail Operator v1.28.3)
- **cert-manager**: v1.15.3
- **MetalLB**: For load balancer support in kind
- **Gateway API**: v1.4.0
- **Istio CNI**: Shared container network interface

### Kuadrant Platform
- **Kuadrant Operator**: Latest from helm repo
- **Authorino**: API authentication/authorization engine
- **Limitador**: Rate limiting service
- **Kuadrant CR**: Enables mTLS support

### Policies (Optional)
- **TLSPolicy**: HTTPS termination with custom CA certificates
- **AuthPolicy**: API Key authentication (Bearer token)
- **RateLimitPolicy**: 5 requests per 10 seconds

## Certificate Details

### Root CA Configuration (Mesh mTLS)

- **Lifetime**: 10 years (87600 hours)
- **Issuer**: `selfsigned-issuer` (ClusterIssuer)
- **Trust Domain**: `10.89.0.0.nip.io`
- **Management**: cert-manager
- **Purpose**: Signs workload certificates for service mesh mTLS

### Gateway Certificate Configuration (HTTPS)

- **Issuer**: `ingress-selfsigned-issuer` (ClusterIssuer)
- **Management**: Auto-created and renewed by TLSPolicy
- **Purpose**: HTTPS termination at gateway

**Note**: Gateway and mesh use **separate certificate authorities**.

### Certificate Hierarchy

```
1. Mesh mTLS Certificates:
   selfsigned-issuer (ClusterIssuer)
   └── istio-root-ca (Certificate - 10 years)
       └── istio-root-ca-secret (Secret)
           └── cacerts (Istio secret)
               ├── ca-cert.pem
               ├── ca-key.pem
               ├── root-cert.pem
               └── cert-chain.pem
               └── Used by: Istiod (signs workload certs)

2. Gateway HTTPS Certificates (separate):
   ingress-selfsigned-issuer (ClusterIssuer)
   └── gateway cert (auto-created by TLSPolicy)
       └── Used by: Gateway HTTPS listener
```

**Certificate Purposes:**
- **Mesh Certificates**: Root CA (10 years) → Workload certs (auto-rotated by Istio)
- **Gateway Certificate**: Self-signed, managed by TLSPolicy (auto-renewed by cert-manager)

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

## Kuadrant Security Policies

The example includes optional Kuadrant policies to secure the echo-api through the ingress gateway.

### Available Policies
1. TLSPolicy - HTTPS with Custom Certificates
2. AuthPolicy - API Key Authentication
3. RateLimitPolicy - API Protection

### Install

```bash
# Install everything including policies
make setup-with-kuadrant

# Or add kuadrant and its policies to existing setup
make setup-kuadrant
```

### Policy Architecture

```
Client Request
    ↓
Gateway (HTTPS - TLSPolicy)
    ↓
AuthPolicy (API Key validation)
    ↓
RateLimitPolicy (10 req/min)
    ↓
HTTPRoute (echo-route)
    ↓
echo-api Service
```

### Testing the Complete Flow

```bash
# Get gateway IP
export INGRESS_IP=$(kubectl get gateway/kuadrant-ingressgateway -n ingress-gateways -o jsonpath='{.status.addresses[0].value}')
# Test HTTPS with auth and rate limiting
curl -k \
  -H "Authorization: Bearer secret-api-key-12345" \
  --insecure \ # Because of the self signed certs
  https://demo.$INGRESS_IP.nip.io/echo

# Expected: JSON response with echo data
# HTTP headers will show X-Auth-Data: authenticated
```

### Policy Details

**TLSPolicy** (`config/kuadrant/tlspolicy.yaml`):
- Targets: Gateway `kuadrant-ingressgateway`
- Certificate: Managed by cert-manager

**RateLimitPolicy** (`config/kuadrant/ratelimitpolicy.yaml`):
- Targets: HTTPRoute `echo-route`
- Limit: 5 requests per 10 seconds
- Scope: Global (across all clients)

**AuthPolicy** (`config/kuadrant/authpolicy.yaml`):
- Targets: HTTPRoute `echo-route`
- Method: API Key authentication
- Location: `Authorization: Bearer <key>` header
- Secret: `api-key-1` in `kuadrant-system` namespace

## Cleanup

From repository root:
```bash
make clean
```

This deletes the kind cluster and all resources.
