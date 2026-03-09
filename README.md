# Multi-Mesh App Security with Kuadrant

This repository demonstrates Istio service mesh configurations with Kuadrant and custom CA certificates managed by cert-manager.

## Examples

### 1. [Single Cluster, Single Mesh](examples/single-cluster-single-mesh/)
Demonstrates a complete Istio service mesh with custom CA certificates.

**Features:**
- One Kubernetes cluster (kind)
- One Istio mesh
- Custom CA certificates via cert-manager
- mTLS communication between workloads
- Kuadrant integration

**Run:**
```bash
make setup-example-1
```

**Docs:** [examples/single-cluster-single-mesh/README.md](examples/single-cluster-single-mesh/README.md)


#### Architecture Overview

##### Example 1: Single Mesh

```mermaid
graph TB
    subgraph Cluster["Kubernetes Cluster (kind-cluster-a)"]
        subgraph NS_MetalLB["metallb-system namespace"]
            MetalLB[MetalLB Load Balancer]
        end

        subgraph NS_CertManager["cert-manager namespace"]
            CertManager[cert-manager]
        end

        subgraph NS_Istio["istio-system namespace"]
            SailOperator[Sail Operator]
            Istiod[Istiod Control Plane]
            PeerAuth[PeerAuthentication<br/>mode: PERMISSIVE/STRICT]
            RootCACert[Certificate<br/>istio-root-ca]
            CacertsSecret[Secret<br/>cacerts]
        end

        subgraph NS_CNI["istio-cni namespace"]
            IstioCNI[Istio CNI]
        end

        subgraph NS_Kuadrant["kuadrant-system namespace"]
            KuadrantOp[Kuadrant Operator]
            KuadrantCR[Kuadrant CR<br/>mtls: enabled]
        end

        subgraph NS_Gateway["ingress-gateways namespace"]
            GW[Gateway<br/>kuadrant-ingressgateway<br/>gatewayClassName: istio<br/>listener: HTTP:80<br/>hostname: demo.10.89.0.0.nip.io]
        end

        subgraph NS_MeshApps["mesh-demo-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
            HTTPRoute[HTTPRoute<br/>echo-route<br/>path: /echo]
            EchoSvc[Service<br/>echo-api<br/>port: 3000]
            EchoDep[Deployment<br/>echo-api<br/>+ Envoy Sidecar<br/>+ Workload Cert]
        end

        subgraph NS_MeshClient["mesh-client-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
            CurlMeshSvc[Service<br/>curl-client<br/>port: 8080]
            CurlMeshDep[Deployment<br/>curl-client<br/>+ Envoy Sidecar<br/>+ Workload Cert]
        end

        subgraph NS_NoMeshClient["no-mesh-client-apps namespace"]
            CurlNoMeshSvc[Service<br/>curl-client<br/>port: 8080]
            CurlNoMeshDep[Deployment<br/>curl-client<br/>no sidecar]
        end
    end

    External[External Traffic<br/>demo.10.89.0.0.nip.io] --> MetalLB
    MetalLB --> GW
    GW -.parentRef.-> HTTPRoute
    HTTPRoute -.backendRef.-> EchoSvc
    EchoSvc --> EchoDep

    CurlMeshDep -.mTLS.-> EchoSvc
    CurlNoMeshDep -.plain HTTP.-> EchoSvc

    CertManager -.manages.-> RootCACert
    RootCACert -.provides.-> CacertsSecret
    CacertsSecret -.used by.-> Istiod
    Istiod -.issues workload certs.-> EchoDep
    Istiod -.issues workload certs.-> CurlMeshDep

    Istiod -.manages.-> GW
    KuadrantOp -.manages.-> GW
    Istiod -.injects.-> EchoDep
    Istiod -.injects.-> CurlMeshDep
    PeerAuth -.enforces mTLS.-> Istiod

    style NS_MeshApps fill:#e1f5ff
    style NS_MeshClient fill:#e1ffe1
    style NS_NoMeshClient fill:#ffe1e1
    style NS_Gateway fill:#fff4e1
    style NS_Kuadrant fill:#ffe1f5
    style NS_Istio fill:#f5e1ff
    style NS_CertManager fill:#fff0e6
    style GW fill:#ffd700
    style HTTPRoute fill:#90ee90
    style EchoDep fill:#87ceeb
    style CurlMeshDep fill:#98fb98
    style CurlNoMeshDep fill:#ffb6c1
    style PeerAuth fill:#dda0dd
    style RootCACert fill:#ffa07a
    style CacertsSecret fill:#ff8c42
    style CertManager fill:#ff7f50
```

---

### 2. [Single Cluster, Dual Mesh](examples/single-cluster-dual-mesh/)
Demonstrates two independent Istio meshes in the same cluster with shared root CA.

**Features:**
- One Kubernetes cluster (kind)
- Two independent Istio meshes
- Shared root CA for cross-mesh mTLS
- Separate control planes and trust domains
- Cross-mesh secure communication

**Run:**
```bash
make setup-example-2
```

**Docs:** [examples/single-cluster-dual-mesh/README.md](examples/single-cluster-dual-mesh/README.md)

##### Example 2: Dual Mesh

```mermaid
graph TB
    subgraph Cluster["Kubernetes Cluster (kind-cluster-a)"]
        subgraph NS_CertManager["cert-manager namespace"]
            CertManager[cert-manager]
            RootCA[Shared Root CA]
        end

        subgraph NS_CNI["istio-cni namespace"]
            IstioCNI[Istio CNI]
        end

        subgraph Mesh1["Mesh-1"]
            subgraph NS_Istio1["istio-system namespace"]
                Istiod1[Istiod]
                PeerAuth1[PeerAuthentication<br/>STRICT]
            end

            subgraph NS_Apps1["mesh-demo-apps namespace"]
                Echo1[echo-api<br/>+ Sidecar]
                EchoSvc1[Service<br/>echo-api]
            end

            subgraph NS_Client1["mesh-client-apps namespace"]
                Curl1[curl-client<br/>+ Sidecar]
                SE1[ServiceEntry<br/>echo-api-2.mesh-demo-apps-2]
            end
        end

        subgraph Mesh2["Mesh-2"]
            subgraph NS_Istio2["istio-system-2 namespace"]
                Istiod2[Istiod]
                PeerAuth2[PeerAuthentication<br/>STRICT]
            end

            subgraph NS_Apps2["mesh-demo-apps-2 namespace"]
                Echo2[echo-api-2<br/>+ Sidecar]
                EchoSvc2[Service<br/>echo-api-2]
            end

            subgraph NS_Client2["mesh-client-apps-2 namespace"]
                Curl2[curl-client<br/>+ Sidecar]
                SE2[ServiceEntry<br/>echo-api.mesh-demo-apps]
            end
        end
    end

    CertManager -.manages.-> RootCA
    RootCA -.shared by.-> Istiod1
    RootCA -.shared by.-> Istiod2

    Istiod1 -.injects.-> Echo1
    Istiod1 -.injects.-> Curl1
    Istiod2 -.injects.-> Echo2
    Istiod2 -.injects.-> Curl2

    EchoSvc1 --> Echo1
    EchoSvc2 --> Echo2

    Curl1 -.intra-mesh mTLS.-> EchoSvc1
    Curl2 -.intra-mesh mTLS.-> EchoSvc2

    SE1 -.declares.-> EchoSvc2
    SE2 -.declares.-> EchoSvc1
    Curl1 -.cross-mesh mTLS.-> EchoSvc2
    Curl2 -.cross-mesh mTLS.-> EchoSvc1

    style Mesh1 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Mesh2 fill:#ffe1f5,stroke:#cc0066,stroke-width:2px
    style NS_CertManager fill:#fff0e6
    style NS_CNI fill:#fff0f0
    style NS_Istio1 fill:#cce6ff
    style NS_Istio2 fill:#ffcce6
    style NS_Apps1 fill:#d9ecff
    style NS_Apps2 fill:#ffd9ec
    style NS_Client1 fill:#e6f2ff
    style NS_Client2 fill:#ffe6f2
    style CertManager fill:#ff7f50
    style RootCA fill:#ffa07a
    style Istiod1 fill:#87ceeb
    style Istiod2 fill:#dda0dd
    style Echo1 fill:#87ceeb
    style Echo2 fill:#dda0dd
    style Curl1 fill:#98fb98
    style Curl2 fill:#ffb6c1
    style SE1 fill:#ffd700
    style SE2 fill:#ffd700
```

---

## Quick Start

Choose an example and run:

```bash
# Example 1 - Single mesh with custom certificates
make setup-example-1

# Example 2 - Dual mesh with shared CA
make setup-example-2
```

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- kubectl
- helm
- jq
- yq

## Cluster Management

```bash
# Create cluster
make create-cluster-a

# Delete cluster
make delete-cluster-a

# Delete all clusters
make clean
```

## Repository Structure

```
euro-info/
├── Makefile                              # Top-level orchestrator
├── README.md                             # This file
├── kind/                                 # Shared cluster configs
│   ├── kind-cluster-a.yaml
│   └── kind-cluster-b.yaml
├── examples/
│   ├── single-cluster-single-mesh/      # Example 1
│   │   ├── README.md
│   │   ├── Makefile
│   │   ├── config/
│   │   │   ├── cert-manager/
│   │   │   ├── istio/
│   │   │   ├── apps/
│   │   │   ├── kuadrant/
│   │   │   └── metallb/
│   │   └── scripts/
│   │       └── create-istio-cacerts.sh
│   │
│   └── single-cluster-dual-mesh/        # Example 2
│       ├── README.md
│       ├── Makefile
│       ├── config/
│       │   ├── cert-manager/
│       │   ├── istio/
│       │   ├── apps/
│       │   └── metallb/
│       └── scripts/
│           └── create-istio-cacerts.sh
```

## TODO

### ✅ 1. Custom Certificates for mTLS with cert-manager
- [x] Create root CA certificate using cert-manager
- [x] Configure Issuer/ClusterIssuer for custom certificates
- [x] Generate CA certificates (using single-level hierarchy)
- [x] Document certificate creation process
- [x] Configure Istio to use custom certificates from cert-manager
- [x] Validate mTLS with custom certificates
- [x] Refactor into example-1

**Status:** Complete. See [Example 1](examples/single-cluster-single-mesh/).

**Certificate Details:**
- Root CA lifetime: 10 years
- Single-level hierarchy (root CA directly signs workload certificates)
- Certificates managed by cert-manager
- Trust domain: `10.89.0.0.nip.io`

---

### ✅ 2. Two Service Meshes in Same Cluster
- [x] Deploy second Istio control plane (mesh-2)
- [x] Configure separate istio-system-2 namespace
- [x] Set up mesh-1 and mesh-2 with separate discovery
- [x] Share same custom certificates across both meshes
- [x] Configure mTLS between services in different meshes
- [x] Deploy demo apps/curl clients in each mesh namespace
- [x] Test cross-mesh communication with shared certificates
- [x] Add architecture diagram with dual mesh setup
- [x] Document mesh isolation and certificate sharing

**Status:** Complete. See [Example 2](examples/single-cluster-dual-mesh/).

---

### 🚧 3. Secure echo-api with Kuadrant

#### Part 1: Single Cluster Single Mesh
- [x] Configure TLSPolicy for echo-api using custom certificates
- [x] Implement AuthPolicy for authentication
- [x] Add RateLimitPolicy for API protection
- [x] Test HTTPS access to echo-api through gateway
- [x] Validate certificate chain and mTLS end-to-end
- [x] Test RateLimit and Auth Policies
- [x] Update Docs with Kuadrant security configuration

#### Part 2: Single Cluster Dual Mesh
Apply the above for `echo-api` in `demo-apps` namespace, `demo-apps-2` won't be protected
- [ ] Configure TLSPolicy for echo-api using custom certificates
- [ ] Implement AuthPolicy for authentication
- [ ] Add RateLimitPolicy for API protection
- [ ] Test HTTPS access to echo-api through gateway
- [ ] Validate certificate chain and mTLS end-to-end
- [ ] Connect with Gateway and HTTPRoute `echo-api-2` but unprotected
- [ ] Document Kuadrant security configuration

---

### 4. Multi-Cluster with Same Mesh Configuration
- [ ] Set up cluster-b with same Istio version and configuration
- [ ] Configure shared root CA across both clusters
- [ ] Distribute custom certificates to cluster-a and cluster-b
- [ ] Configure east-west gateway for cross-cluster communication
- [ ] Set up service mesh federation between clusters
- [ ] Configure cross-cluster service discovery
- [ ] Enable mTLS for cross-cluster traffic using shared certificates
- [ ] Deploy echo-api and curl-client across both clusters
- [ ] Test cross-cluster mTLS communication
- [ ] Configure multi-cluster gateway and routing
- [ ] Add multi-cluster architecture diagram
- [ ] Document multi-cluster certificate management

---
