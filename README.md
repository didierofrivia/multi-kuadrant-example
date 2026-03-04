# Multi-Cluster App Security with Kuadrant

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

## Quick Start

Choose an example and run:

```bash
# Example 1 - Single mesh with custom certificates
make setup-example-1
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

### 🚧 2. Two Service Meshes in Same Cluster
- [ ] Deploy second Istio control plane (mesh-2)
- [ ] Configure separate istio-system-2 namespace
- [ ] Set up mesh-1 and mesh-2 with separate discovery
- [ ] Share same custom certificates across both meshes
- [ ] Configure mTLS between services in different meshes
- [ ] Deploy demo apps/curl clients in each mesh namespace
- [ ] Test cross-mesh communication with shared certificates
- [ ] Add architecture diagram with dual mesh setup
- [ ] Document mesh isolation and certificate sharing

**Status:** In progress. See [Example 2](examples/single-cluster-dual-mesh/).

---

### 3. Secure echo-api with Kuadrant using Custom Certificates
- [ ] Configure TLSPolicy for echo-api using custom certificates
- [ ] Implement AuthPolicy for authentication
- [ ] Add RateLimitPolicy for API protection
- [ ] Test HTTPS access to echo-api through gateway
- [ ] Validate certificate chain and mTLS end-to-end
- [ ] Document Kuadrant security configuration

---

### 4. Multi-Cluster with Same Mesh Configuration using Custom Certificates
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
