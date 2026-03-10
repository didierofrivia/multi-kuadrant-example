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
│   │   └── PeerAuthentication (mTLS mode: STRICT)
│   ├── mesh-demo-apps (namespace)
│   │   └── echo-api (with sidecar, mesh=mesh-1)
│   └── mesh-client-apps (namespace)
│       └── curl-client (with sidecar, mesh=mesh-1)
│
└── Mesh-2
    ├── istio-system-2 (namespace)
    │   ├── istiod (control plane)
    │   ├── cacerts (from shared root CA)
    │   └── PeerAuthentication (mTLS mode: STRICT)
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

---

## Kuadrant Security Policies (Optional)

This example can be extended with Kuadrant policies to demonstrate selective route-level security in a dual-mesh environment.

### Architecture Overview

The Kuadrant setup uses a **single gateway** with **route-level policy targeting**:

**Gateway Configuration**:
- Name: `kuadrant-ingressgateway` in `ingress-gateways` namespace
- Hostname: `demo.10.89.0.0.nip.io`
- Managed by: Istiod in `istio-system` (mesh-1)
- TLSPolicy: Applied at gateway level (HTTPS for all traffic)

**Route-Level Policies**:
- **Mesh-1 Route** (`/echo`): Protected with AuthPolicy + RateLimitPolicy
- **Mesh-2 Route** (`/echo2`): Unprotected (no policies)

**Cross-Mesh Routing Architecture**:
- Gateway is managed by mesh-1's Istiod (in `istio-system`)
- HTTPRoutes are in their respective application namespaces:
  - `echo-route` in `mesh-demo-apps` (mesh-1)
  - `echo-route-2` in `mesh-demo-apps-2` (mesh-2)
- Mesh-1's Istiod is configured to discover the `mesh-demo-apps-2` namespace
- A ServiceEntry makes mesh-2's service discoverable by the gateway

**Discovery Configuration**:
Mesh-1's Istiod has an expanded discovery selector to see both:
1. Namespaces labeled with `mesh=mesh-1` (standard mesh-1 namespaces)
2. The `mesh-demo-apps-2` namespace specifically (for HTTPRoute discovery)

This allows the gateway (managed by mesh-1) to route to services in both meshes while keeping HTTPRoutes in their application namespaces.

This demonstrates **granular policy control** at the HTTPRoute level within a multi-mesh environment.

### Installation

#### Complete Setup with Kuadrant

From repository root:
```bash
cd examples/single-cluster-dual-mesh
make setup-with-kuadrant
```

This installs everything (both meshes + Kuadrant + gateway + policies).

#### Add Kuadrant to Existing Setup

If you already ran `make setup`:
```bash
make setup-kuadrant
```

### Components

**Kuadrant Platform** (deployed in `kuadrant-system`):
- Kuadrant Operator
- Authorino & its Operator (authentication/authorization)
- Limitador & its Operator (rate limiting)

**Gateway** (in `ingress-gateways`, managed by mesh-1):
- Single HTTPS listener on port 443
- TLSPolicy: Auto-managed certificates for HTTPS
- Routes to both mesh-1 and mesh-2 services

**Policies**:
- **TLSPolicy**: Gateway-level (applies to all routes)
- **AuthPolicy**: Route-level (mesh-1 `/echo` only)
- **RateLimitPolicy**: Route-level (mesh-1 `/echo` only)

### Policy Details

#### Gateway-Level Policy

**TLSPolicy**:
- Target: Gateway `kuadrant-ingressgateway`
- Issuer: `ingress-selfsigned-issuer` (ClusterIssuer)
- Certificate: Auto-created and renewed by Kuadrant
- Effect: All traffic uses HTTPS (both `/echo` and `/echo2`)

#### Route-Level Policies (Mesh-1 Only)

**AuthPolicy**:
- Target: HTTPRoute `echo-route` (mesh-1, `/echo` path)
- Method: API Key via `Authorization: Bearer` header
- Secret: `api-key-1` in `kuadrant-system`
- Test API Key: `secret-api-key-12345`
- Effect: `/echo` requires auth, `/echo2` does not

**RateLimitPolicy**:
- Target: HTTPRoute `echo-route` (mesh-1, `/echo` path)
- Limit: 5 requests per 10 seconds
- Scope: Global
- Effect: `/echo` has rate limit, `/echo2` does not

### Access Patterns

| Path     | Mesh   | HTTPS | Auth Required | Rate Limited |
|----------|--------|-------|---------------|--------------|
| `/echo`  | mesh-1 | ✅     | ✅             | ✅ (5/10s)    |
| `/echo2` | mesh-2 | ✅     | ❌             | ❌            |

### Testing

#### Get Gateway IP

```bash
make get-gateway-ip
```

Expected output:
```
Gateway IP: 10.89.0.0
```

#### Test Protected Route (Mesh-1 `/echo`)

**Test Authentication**:
```bash
make test-auth
```

Expected:
- Without API key: HTTP 401
- With valid key: HTTP 200 + `X-Auth-Data: authenticated`
- With invalid key: HTTP 401

**Test Rate Limiting**:
```bash
make test-ratelimit
```

Expected:
- Requests 1-5: HTTP 200
- Requests 6-10: HTTP 429 (rate limited)

#### Test Unprotected Route (Mesh-2 `/echo2`)

```bash
make test-unprotected
```

Expected:
- All requests: HTTP 200
- No authentication required
- No rate limiting enforced

### Manual Testing

```bash
# Get gateway IP
export INGRESS_IP=$(kubectl get gateway/kuadrant-ingressgateway \
  -n ingress-gateways -o jsonpath='{.status.addresses[0].value}')

# Test mesh-1 (protected) - requires auth
curl -k https://demo.$INGRESS_IP.nip.io/echo
# Expected: 401 Unauthorized

curl -k -H "Authorization: Bearer secret-api-key-12345" \
  https://demo.$INGRESS_IP.nip.io/echo | jq
# Expected: 200 OK with response data

# Test mesh-2 (unprotected) - no auth needed
curl -k https://demo.$INGRESS_IP.nip.io/echo2 | jq
# Expected: 200 OK with response data
```

### Architecture Diagram

```mermaid
graph TB
    subgraph Cluster["Kubernetes Cluster (kind-cluster-a)"]
        subgraph NS_CertManager["cert-manager namespace"]
            CertManager[cert-manager]
            RootCA[Shared Root CA<br/>for mesh mTLS]
            IngressIssuer[ClusterIssuer<br/>ingress-selfsigned-issuer]
        end

        subgraph NS_CNI["istio-cni namespace"]
            IstioCNI[Istio CNI<br/>shared by both meshes]
        end

        subgraph Mesh1["Mesh-1"]
            subgraph NS_Istio1["istio-system namespace"]
                Istiod1[Istiod Control Plane]
                PeerAuth1[PeerAuthentication<br/>mode: STRICT]
                CacertsSecret1[Secret<br/>cacerts]
            end

            subgraph NS_Kuadrant["kuadrant-system namespace<br/>(mesh=mesh-1, istio.io/rev=default)"]
                KuadrantOp[Kuadrant Operator]
                Authorino[Authorino<br/>+ Sidecar]
                Limitador[Limitador<br/>+ Sidecar]
                APIKey[Secret: api-key-1]
            end

            subgraph NS_GW["ingress-gateways namespace<br/>(mesh=mesh-1)"]
                GW[Gateway<br/>kuadrant-ingressgateway<br/>HTTPS:443<br/>demo.10.89.0.0.nip.io]
                TLSPolicy[TLSPolicy]
                SE_Mesh2[ServiceEntry<br/>echo-api-2]
            end

            subgraph NS_Apps1["mesh-demo-apps namespace<br/>(mesh=mesh-1, istio.io/rev=default)"]
                Route1[HTTPRoute<br/>echo-route<br/>path: /echo]
                AuthPolicy[AuthPolicy]
                RLPolicy[RateLimitPolicy]
                Echo1[echo-api<br/>Service + Deployment<br/>+ Sidecar]
            end

            subgraph NS_Client1["mesh-client-apps namespace<br/>(mesh=mesh-1, istio.io/rev=default)"]
                Curl1[curl-client<br/>Deployment<br/>+ Sidecar]
                SE1[ServiceEntry<br/>echo-api-2.mesh-demo-apps-2]
            end
        end

        subgraph Mesh2["Mesh-2"]
            subgraph NS_Istio2["istio-system-2 namespace"]
                Istiod2[Istiod Control Plane]
                PeerAuth2[PeerAuthentication<br/>mode: STRICT]
                CacertsSecret2[Secret<br/>cacerts]
            end

            subgraph NS_Apps2["mesh-demo-apps-2 namespace<br/>(mesh=mesh-2, istio.io/rev=default-2)<br/>(discovered by mesh-1)"]
                Route2[HTTPRoute<br/>echo-route-2<br/>path: /echo2]
                Echo2[echo-api-2<br/>Service + Deployment<br/>+ Sidecar]
            end

            subgraph NS_Client2["mesh-client-apps-2 namespace<br/>(mesh=mesh-2, istio.io/rev=default-2)"]
                Curl2[curl-client<br/>Deployment<br/>+ Sidecar]
                SE2[ServiceEntry<br/>echo-api.mesh-demo-apps]
            end
        end
    end

    %% External traffic flow
    External[External Traffic<br/>demo.*.nip.io] --> GW

    %% Gateway policy enforcement
    GW -.enforces.-> TLSPolicy
    TLSPolicy -.uses.-> IngressIssuer

    %% Routing
    GW -.routes to.-> Route1
    GW -.routes to.-> Route2

    %% Mesh-1 route policies
    Route1 -.enforces.-> AuthPolicy
    Route1 -.enforces.-> RLPolicy
    Route1 -.backend.-> Echo1

    %% Cross-mesh discovery and routing
    SE_Mesh2 -.discovers.-> Echo2
    Route2 -.backend.-> Echo2

    %% Kuadrant policy enforcement
    AuthPolicy -.validated by.-> Authorino
    Authorino -.uses.-> APIKey
    RLPolicy -.enforced by.-> Limitador

    %% Certificate management
    CertManager -.manages.-> IngressIssuer
    CertManager -.manages.-> RootCA
    RootCA -.shared by.-> CacertsSecret1
    RootCA -.shared by.-> CacertsSecret2
    CacertsSecret1 -.used by.-> Istiod1
    CacertsSecret2 -.used by.-> Istiod2

    %% Istio control plane management
    Istiod1 -.manages.-> GW
    Istiod1 -.injects sidecars.-> Authorino
    Istiod1 -.injects sidecars.-> Limitador
    Istiod1 -.injects sidecars.-> Echo1
    Istiod1 -.injects sidecars.-> Curl1
    Istiod2 -.injects sidecars.-> Echo2
    Istiod2 -.injects sidecars.-> Curl2

    %% mTLS enforcement
    PeerAuth1 -.enforces mTLS.-> Istiod1
    PeerAuth2 -.enforces mTLS.-> Istiod2

    %% Intra-mesh communication
    Curl1 -.intra-mesh mTLS.-> Echo1
    Curl2 -.intra-mesh mTLS.-> Echo2

    %% Cross-mesh communication
    SE1 -.declares.-> Echo2
    SE2 -.declares.-> Echo1
    Curl1 -.cross-mesh mTLS.-> Echo2
    Curl2 -.cross-mesh mTLS.-> Echo1

    %% Styling - Mesh boundaries (solid)
    style Mesh1 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Mesh2 fill:#ffe1f5,stroke:#cc0066,stroke-width:2px

    %% Styling - Infrastructure namespaces (dashed)
    style NS_CertManager fill:#fff0e6,stroke-dasharray: 5 5
    style NS_CNI fill:#f5f5f5,stroke-dasharray: 5 5

    %% Styling - Mesh-1 namespaces (dashed, blue tint)
    style NS_Istio1 fill:#cce6ff,stroke-dasharray: 5 5
    style NS_Kuadrant fill:#d9ecff,stroke-dasharray: 5 5
    style NS_GW fill:#e6f2ff,stroke-dasharray: 5 5
    style NS_Apps1 fill:#d9ecff,stroke-dasharray: 5 5
    style NS_Client1 fill:#e6f2ff,stroke-dasharray: 5 5

    %% Styling - Mesh-2 namespaces (dashed, pink tint)
    style NS_Istio2 fill:#ffcce6,stroke-dasharray: 5 5
    style NS_Apps2 fill:#ffd9ec,stroke-dasharray: 5 5
    style NS_Client2 fill:#ffe6f2,stroke-dasharray: 5 5

    %% Styling - Components
    style GW fill:#ffd700
    style TLSPolicy fill:#ff6b6b
    style AuthPolicy fill:#ff8c42
    style RLPolicy fill:#ff8c42
    style Route1 fill:#ffb347
    style Route2 fill:#90ee90
    style Echo1 fill:#87ceeb
    style Echo2 fill:#dda0dd
    style Curl1 fill:#98fb98
    style Curl2 fill:#ffb6c1
    style Istiod1 fill:#87ceeb
    style Istiod2 fill:#dda0dd
    style PeerAuth1 fill:#87ceeb
    style PeerAuth2 fill:#dda0dd
    style CacertsSecret1 fill:#ff8c42
    style CacertsSecret2 fill:#ff8c42
    style KuadrantOp fill:#da70d6
    style Authorino fill:#da70d6
    style Limitador fill:#da70d6
    style CertManager fill:#ff7f50
    style RootCA fill:#ffa07a
    style IngressIssuer fill:#ffa07a
    style SE1 fill:#ffd700
    style SE2 fill:#ffd700
    style SE_Mesh2 fill:#ffd700
```

### How It Works

#### Request Flow - Protected Route (`/echo`)

```
1. Client → HTTPS request to demo.10.89.0.0.nip.io/echo
2. Gateway → TLSPolicy terminates TLS
3. HTTPRoute echo-route → Matches path /echo
4. AuthPolicy → Validates API key (401 if missing/invalid)
5. RateLimitPolicy → Checks rate limit (429 if exceeded)
6. Request forwarded → echo-api in mesh-1
7. Response returned to client
```

#### Request Flow - Unprotected Route (`/echo2`)

```
1. Client → HTTPS request to demo.10.89.0.0.nip.io/echo2
2. Gateway → TLSPolicy terminates TLS
3. HTTPRoute echo-route-2 → Matches path /echo2
4. Request forwarded → echo-api-2 in mesh-2 (no policies)
5. Response returned to client
```

#### Cross-Mesh Service Discovery

The gateway is managed by mesh-1's Istiod. To enable routing to both meshes:

* **Expanded Discovery Selector**: Mesh-1's Istiod is configured to discover:
   - All namespaces with `mesh=mesh-1` label (standard mesh-1 namespaces)
   - The `mesh-demo-apps-2` namespace specifically (for HTTPRoute in mesh-2)


This configuration allows:
- HTTPRoutes to remain in application namespaces (Gateway API best practice)
- The gateway to discover and route to services in both meshes
- Policies to be applied in application namespaces alongside the routes

### Customization

#### Change API Key

```bash
kubectl edit secret -n kuadrant-system api-key-1
```

#### Change Rate Limit

```bash
kubectl edit ratelimitpolicy -n mesh-demo-apps echo-api-ratelimit
```

Change `limit` and `window`:
```yaml
limits:
  "global":
    rates:
      - limit: 10        # Number of requests
        window: 60s      # Time window
```

#### Disable Policies

```bash
# Disable authentication (mesh-1 becomes open)
kubectl delete authpolicy -n mesh-demo-apps echo-api-auth

# Disable rate limiting (mesh-1 has no limits)
kubectl delete ratelimitpolicy -n mesh-demo-apps echo-api-ratelimit

# Disable TLS policy (loses auto-cert management)
kubectl delete tlspolicy -n ingress-gateways gateway-tls-policy
```

---

## Cleanup

From repository root:
```bash
make clean
```

This deletes the kind cluster and all resources.

## References

- [Istio Multi-Mesh Documentation](https://istio.io/latest/docs/setup/install/multiple-controlplanes/)
- [Kuadrant Documentation](https://docs.kuadrant.io/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Sail Operator Documentation](https://github.com/istio-ecosystem/sail-operator)
