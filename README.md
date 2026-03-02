# Multi Cluster App Security with Kuadrant

## Single Cluster Architecture

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
            EchoDep[Deployment<br/>echo-api<br/>+ Envoy Sidecar]
        end

        subgraph NS_MeshClient["mesh-client-apps namespace<br/>(istio-discovery=enabled, istio-injection=enabled)"]
            CurlMeshSvc[Service<br/>curl-client<br/>port: 8080]
            CurlMeshDep[Deployment<br/>curl-client<br/>+ Envoy Sidecar]
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
    style GW fill:#ffd700
    style HTTPRoute fill:#90ee90
    style EchoDep fill:#87ceeb
    style CurlMeshDep fill:#98fb98
    style CurlNoMeshDep fill:#ffb6c1
    style PeerAuth fill:#dda0dd
    style DestRule fill:#87ceeb
```
