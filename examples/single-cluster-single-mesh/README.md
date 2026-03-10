# Example 1: Single Cluster, Single Mesh with Custom Certificates

This example demonstrates a complete Istio service mesh setup with custom CA certificates managed by cert-manager.

## Features

### Core Setup
- Single Kubernetes cluster (kind)
- Single Istio service mesh with mTLS
- Custom CA certificates via cert-manager (10-year root CA)
- Service-to-service mTLS communication
- MetalLB for load balancer support
- Gateway API v1.4.0

### Kuadrant Security Policies
- **TLSPolicy**: HTTPS termination with automatic certificate management
- **AuthPolicy**: API key authentication via Authorino
- **RateLimitPolicy**: Request rate limiting (5 req/10s) via Limitador

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- kubectl
- helm
- jq
- yq

## Quick Start

### Basic Setup (without Kuadrant policies)

**From Repository Root:**
```bash
make setup-example-1
```

**From This Directory:**
```bash
make setup
```

This installs:
- Istio service mesh with custom CA certificates
- cert-manager for certificate management
- MetalLB for load balancing
- Echo API application
- Test clients (with and without sidecars)

### With Kuadrant Security Policies

**From This Directory:**
```bash
make setup-with-kuadrant
```

This installs everything above **plus**:
- Kuadrant operator (Authorino + Limitador)
- TLSPolicy (HTTPS with auto-managed certificates)
- AuthPolicy (API key authentication)
- RateLimitPolicy (5 requests per 10 seconds)

**Test the policies:**
```bash
make test-auth        # Test API key authentication
make test-ratelimit   # Test rate limiting
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

        subgraph NS_CNI["istio-cni namespace"]
            IstioCNI[Istio CNI]
        end

        subgraph Mesh["Service Mesh<br/>Trust Domain: nip.io"]
            subgraph NS_Istio["istio-system namespace"]
                SailOperator[Sail Operator]
                Istiod[Istiod Control Plane]
                PeerAuth[PeerAuthentication<br/>mode: PERMISSIVE/STRICT]
                CacertsSecret[Secret<br/>cacerts]
            end

            subgraph NS_Kuadrant["kuadrant-system namespace<br/>(istio-discovery=enabled)"]
                KuadrantOp[Kuadrant Operator]
                KuadrantCR[Kuadrant CR<br/>mtls: enabled]
                Authorino[Authorino<br/>+ Sidecar]
                Limitador[Limitador<br/>+ Sidecar]
                APIKeySecret[Secret<br/>api-key-1]
            end

            subgraph NS_Gateway["ingress-gateways namespace<br/>(istio-discovery=enabled)"]
                GW[Gateway<br/>kuadrant-ingressgateway<br/>HTTP: 80, HTTPS: 443]
                TLSPolicy[TLSPolicy]
            end

            subgraph NS_MeshApps["mesh-demo-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
                HTTPRoute[HTTPRoute<br/>echo-route<br/>path: /echo]
                AuthPolicy[AuthPolicy]
                RateLimitPolicy[RateLimitPolicy]
                EchoSvc[Service<br/>echo-api<br/>port: 3000]
                EchoDep[Deployment<br/>echo-api<br/>+ Envoy Sidecar]
            end

            subgraph NS_MeshClient["mesh-client-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
                CurlMeshDep[Deployment<br/>curl-client<br/>+ Envoy Sidecar]
            end
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
    Istiod -.manages.-> GW
    Istiod -.injects.-> Authorino
    Istiod -.injects.-> Limitador
    Istiod -.injects.-> EchoDep
    Istiod -.injects.-> CurlMeshDep
    PeerAuth -.enforces mTLS.-> Istiod

    %% Styling - Mesh boundary (solid)
    style Mesh fill:#e1f5ff,stroke:#0066cc,stroke-width:2px

    %% Styling - Infrastructure namespaces outside mesh (dashed)
    style NS_MetalLB fill:#f0f0f0,stroke-dasharray: 5 5
    style NS_CertManager fill:#fff0e6,stroke-dasharray: 5 5
    style NS_CNI fill:#f5f5f5,stroke-dasharray: 5 5
    style NS_NoMeshClient fill:#ffe1e1,stroke-dasharray: 5 5

    %% Styling - Mesh namespaces (dashed, blue tints)
    style NS_Istio fill:#cce6ff,stroke-dasharray: 5 5
    style NS_Kuadrant fill:#d9ecff,stroke-dasharray: 5 5
    style NS_Gateway fill:#e6f2ff,stroke-dasharray: 5 5
    style NS_MeshApps fill:#d9ecff,stroke-dasharray: 5 5
    style NS_MeshClient fill:#e6f2ff,stroke-dasharray: 5 5

    %% Styling - Components
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

### Kuadrant
- **Kuadrant Operator**: Latest from helm repo
- **Authorino and its Operator**: API authentication/authorization engine
- **Limitador and its Operator**: Rate limiting service

### Policies
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

The example includes optional Kuadrant policies to secure the echo-api through the ingress gateway. These policies demonstrate API management capabilities including TLS termination, authentication, and rate limiting.

### Overview

Kuadrant provides three main policies:

1. **TLSPolicy** - HTTPS termination with automatic certificate management
2. **AuthPolicy** - API key-based authentication via Authorino
3. **RateLimitPolicy** - Request rate limiting via Limitador

### Installation

#### Option 1: Complete Setup with Kuadrant

Install everything including Kuadrant and all policies:

```bash
make setup-with-kuadrant
```

#### Option 2: Add Kuadrant to Existing Setup

If you already ran `make setup`, add Kuadrant and policies:

```bash
make setup-kuadrant
```

#### Option 3: Install Policies Individually

```bash
# Install Kuadrant operator and CR
make install-kuadrant

# Install TLS certificate and policy
make setup-gateway-tls
make install-tlspolicy

# Install rate limiting
make install-ratelimit

# Install authentication
make install-auth
```

### Policy Architecture

```
External HTTPS Request
    ↓
Gateway (port 443)
    ↓
TLSPolicy ← cert-manager (auto-managed certificate)
    ↓
AuthPolicy ← Authorino (validates API key)
    ↓
RateLimitPolicy ← Limitador (enforces rate limit)
    ↓
HTTPRoute (echo-route)
    ↓
echo-api Service (port 3000)
```

### Policy Details

#### 1. TLSPolicy

**Purpose**: Enables HTTPS on the gateway with automatic certificate management.

**Configuration** (`config/kuadrant/tlspolicy.yaml`):
- Targets: Gateway `kuadrant-ingressgateway`
- Issuer: `ingress-selfsigned-issuer` (ClusterIssuer)
- Certificate: Auto-created and renewed by cert-manager
- Protocol: TLS termination at gateway

**What it does**:
- Creates HTTPS listener on port 443
- Automatically provisions TLS certificate
- Handles certificate renewal
- Terminates TLS at the gateway

**Files involved**:
- `config/cert-manager/ingress-issuer.yaml` - Self-signed ClusterIssuer
- `config/kuadrant/tlspolicy.yaml` - TLS policy configuration
- `config/istio/gateway/gateway.yaml` - Gateway with HTTPS listener

#### 2. AuthPolicy

**Purpose**: Requires valid API key for all requests to echo-api.

**Configuration** (`config/kuadrant/authpolicy.yaml`):
- Targets: HTTPRoute `echo-route`
- Method: API Key authentication
- Header: `Authorization: Bearer <api-key>`
- Validator: Authorino
- Secret: `api-key-1` in `kuadrant-system` namespace

**What it does**:
- Validates API key on every request
- Returns HTTP 401 for missing/invalid keys
- Adds `X-Auth-Data: authenticated` header on success
- Integrates with Authorino for validation

**Test API Key**: `secret-api-key-12345`

**Test authentication**:
```bash
make test-auth
```

Expected output:
```
=== Test 1: Request without API key (should fail) ===
HTTP Status: 401

=== Test 2: Request with valid API key (should succeed) ===
{
  "method": "GET",
  "path": "/echo",
  "headers": {
    "X-Auth-Data": "authenticated",
    ...
  }
}

=== Test 3: Request with invalid API key (should fail) ===
HTTP Status: 401
```

#### 3. RateLimitPolicy

**Purpose**: Limits requests to prevent abuse and ensure fair usage.

**Configuration** (`config/kuadrant/ratelimitpolicy.yaml`):
- Targets: HTTPRoute `echo-route`
- Limit: 5 requests per 10 seconds
- Scope: Global (all clients)
- Enforcer: Limitador

**What it does**:
- Tracks request count per time window
- Returns HTTP 429 (Too Many Requests) when limit exceeded
- Resets counter after time window
- Protects backend from overload

**Test rate limiting**:
```bash
make test-ratelimit
```

Expected output (sends 15 requests):
```
Request 1: - HTTP 200
Request 2: - HTTP 200
Request 3: - HTTP 200
Request 4: - HTTP 200
Request 5: - HTTP 200
Request 6: - HTTP 429  ← Rate limit triggered
Request 7: - HTTP 429
...
Request 15: - HTTP 429
```

### Testing

#### Complete Flow Test

Test all policies together:

```bash
# Get gateway IP
export INGRESS_IP=$(kubectl get gateway/kuadrant-ingressgateway -n ingress-gateways -o jsonpath='{.status.addresses[0].value}')

# Test HTTPS with auth and rate limiting
curl -k \
  -H "Authorization: Bearer secret-api-key-12345" \
  https://demo.$INGRESS_IP.nip.io/echo | jq

# Expected: JSON response with echo data
# HTTP headers will show X-Auth-Data: authenticated
```

**Note**: Use `-k` or `--insecure` because the gateway uses a self-signed certificate.

#### Individual Policy Tests

```bash
# Test authentication (3 scenarios)
make test-auth

# Test rate limiting (triggers 429 after 5 requests)
make test-ratelimit
```

### Components

The Kuadrant platform deploys these components:

1. **Kuadrant Operator** - Manages lifecycle of Kuadrant components and enforces TLS/DNS
2. **Authorino and its operator** - Handles authentication and authorization
3. **Limitador and its operator** - Enforces rate limiting policies

These are automatically deployed in the `kuadrant-system` namespace when you run `make install-kuadrant`.

### How It Works

#### Request Flow with All Policies

```
1. Client sends HTTPS request
   ↓
2. Gateway terminates TLS (TLSPolicy)
   - Certificate validated
   - Traffic decrypted
   ↓
3. Authorino validates API key (AuthPolicy)
   - Checks Authorization header
   - Validates against Secret
   - Returns 401 if invalid
   ↓
4. Limitador checks rate limit (RateLimitPolicy)
   - Increments request counter
   - Returns 429 if limit exceeded
   ↓
5. Request forwarded to echo-api
   ↓
6. Response returned to client
```

#### Policy Enforcement Points

- **TLSPolicy**: Enforced at Gateway (ingress-gateways namespace)
- **AuthPolicy**: Enforced at HTTPRoute (mesh-demo-apps namespace)
- **RateLimitPolicy**: Enforced at HTTPRoute (mesh-demo-apps namespace)

### Customization

#### Change API Key

Edit the secret:
```bash
kubectl edit secret -n kuadrant-system api-key-1
```

Or apply a new secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-key-1
  namespace: kuadrant-system
  labels:
    authorino.kuadrant.io/managed-by: authorino
    app: echo-api
stringData:
  api_key: "your-new-api-key"
```

#### Change Rate Limit

Edit the RateLimitPolicy:
```bash
kubectl edit ratelimitpolicy -n mesh-demo-apps echo-api-ratelimit
```

Change `limit` and `window` values:
```yaml
limits:
  "global":
    rates:
      - limit: 10        # Number of requests
        window: 60s      # Time window
```

#### Disable a Policy

```bash
# Disable authentication
kubectl delete authpolicy -n mesh-demo-apps echo-api-auth

# Disable rate limiting
kubectl delete ratelimitpolicy -n mesh-demo-apps echo-api-ratelimit

# Disable TLS
kubectl delete tlspolicy -n ingress-gateways gateway-tls-policy
```

## Cleanup

From repository root:
```bash
make clean
```

This deletes the kind cluster and all resources.

### Learn More

- [Istio Documentation](https://istio.io/latest/docs/)
- [Kuadrant Documentation](https://docs.kuadrant.io/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
