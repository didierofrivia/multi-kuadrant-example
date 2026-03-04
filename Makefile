SAIL_VERSION = 1.28.3
ISTIO_NS = istio-system
CNI_NS = istio-cni
ISTIO_CONFIG_DIR = config/istio

INGRESS_GATEWAY_NS ?= ingress-gateways
INGRESS_IP ?= 10.89.0.0

MESH_APP_NS ?= mesh-demo-apps
MESH_CLIENT_NS ?= mesh-client-apps
NO_MESH_CLIENT_NS ?= no-mesh-client-apps

KUADRANT_NS ?= kuadrant-system
KUADRANT_CONFIG_DIR = config/kuadrant

CERT_MANAGER_CONFIG_DIR = config/cert-manager
SCRIPTS_DIR = scripts

.PHONY: help
help:
	@echo "Available targets:"
	@echo ""
	@echo "Cluster Management:"
	@echo "  create-cluster-a      - Create kind cluster A (ports 8080/8443)"
	@echo "  create-cluster-b      - Create kind cluster B (ports 9080/9443)"
	@echo "  create-clusters       - Create both clusters"
	@echo "  delete-cluster-a      - Delete kind cluster A"
	@echo "  delete-cluster-b      - Delete kind cluster B"
	@echo "  delete-clusters       - Delete both clusters"
	@echo "  clean                 - Delete both clusters (alias)"
	@echo ""
	@echo "Component Installation:"
	@echo "  helm-kuadrant-repo    - Add/Update Kuadrant helm repository"
	@echo "  install-metallb       - Install MetalLB load balancer"
	@echo "  install-cert-manager  - Install cert-manager"
	@echo "  install-istio         - Install Istio through sail operator"
	@echo "  install-dependencies  - Install Gateway API, MetalLB, cert-manager, and Istio"
	@echo "  install-kuadrant      - Install Kuadrant operator"
	@echo "  install-echo-api      - Install echo API test application"
	@echo "  install-curl-client   - Install curl client in separate namespace"
	@echo ""
	@echo "Security Configuration:"
	@echo "  setup-custom-ca       - Create custom CA certificates for Istio (run before install-istio)"
	@echo "  clean-certificates    - Remove all certificate resources"
	@echo "  enable-mtls           - Enable (PERMISSIVE by default) mTLS in the mesh"
	@echo "  mtls-mode-strict      - Switch to STRICT mTLS in the mesh"
	@echo "  mtls-mode-permissive  - Switch to PERMISSIVE mTLS in the mesh"
	@echo "  test-mtls             - Test mTLS communication from client to echo-api"
	@echo ""
	@echo "Cluster Setup:"
	@echo "  install-cluster-a     - Setup cluster A with Kuadrant"
	@echo "  install-cluster-b     - Setup cluster B with Kuadrant"
	@echo "  install               - Install Kuadrant operator in both clusters"
	@echo ""
	@echo "Complete Setup:"
	@echo "  setup-example-1       - Create single cluster, single mesh and install all components"

.PHONY: create-cluster-a
create-cluster-a:
	@echo "Creating cluster A..."
	kind create cluster --config kind/kind-cluster-a.yaml
	@echo "Cluster A created successfully"
	@echo "HTTP: localhost:8080"
	@echo "HTTPS: localhost:8443"

.PHONY: create-cluster-b
create-cluster-b:
	@echo "Creating cluster B..."
	kind create cluster --config kind/kind-cluster-b.yaml
	@echo "Cluster B created successfully"
	@echo "HTTP: localhost:9080"
	@echo "HTTPS: localhost:9443"

.PHONY: create-clusters
create-clusters: create-cluster-a #create-cluster-b
	@echo "Clusters created successfully"

.PHONY: delete-cluster-a
delete-cluster-a:
	@echo "Deleting cluster A..."
	kind delete cluster --name cluster-a

.PHONY: delete-cluster-b
delete-cluster-b:
	@echo "Deleting cluster B..."
	kind delete cluster --name cluster-b

.PHONY: delete-clusters
delete-clusters: delete-cluster-a delete-cluster-b
	@echo "Both clusters deleted"

.PHONY: clean
clean: delete-clusters

.PHONY: helm-kuadrant-repo
helm-kuadrant-repo:
	@echo "Adding/Updating Kuadrant helm repo..."
	helm repo add kuadrant https://kuadrant.io/helm-charts/ --force-update
	helm repo update

.PHONY: install-metallb
install-metallb:
	helm repo add metallb https://metallb.github.io/metallb --force-update
	helm install metallb metallb/metallb \
	--namespace metallb-system \
	--create-namespace \
	--wait
	kubectl -n metallb-system apply -f config/metallb/metallb.yaml


.PHONY: install-cert-manager
install-cert-manager:
	@echo "Installing cert-manager..."
	helm repo add jetstack https://charts.jetstack.io --force-update
	helm install \
		cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version v1.15.3 \
		--set crds.enabled=true

.PHONY: setup-custom-ca
setup-custom-ca:
	@echo "Setting up custom CA certificates for Istio..."
	@echo "Applying root CA certificate configuration..."
	kubectl apply -f $(CERT_MANAGER_CONFIG_DIR)/root-ca.yaml
	@echo "Waiting for certificate to be ready..."
	kubectl wait --for=condition=Ready certificate/istio-root-ca -n $(ISTIO_NS) --timeout=300s
	@echo "Creating Istio cacerts secret..."
	$(SCRIPTS_DIR)/create-istio-cacerts.sh
	@echo "Custom CA setup complete!"

.PHONY: clean-certificates
clean-certificates:
	@echo "Removing all certificate resources..."
	kubectl delete certificate istio-root-ca -n $(ISTIO_NS) --ignore-not-found=true
	kubectl delete secret istio-root-ca-secret -n $(ISTIO_NS) --ignore-not-found=true
	kubectl delete secret cacerts -n $(ISTIO_NS) --ignore-not-found=true
	kubectl delete clusterissuer selfsigned-issuer --ignore-not-found=true
	@echo "Certificate resources removed"

.PHONY: install-istio
install-istio:
	@echo "Installing Istio through sail operator..."
	# Create istio-system namespace first (required for custom CA setup)
	kubectl create namespace $(ISTIO_NS) || true

	# Setup custom CA certificates BEFORE installing Istio
	make setup-custom-ca

	# Install Istio via Sail Operator (will automatically pick up cacerts)
	helm install sail-operator \
		--namespace $(ISTIO_NS) \
		--wait \
		--timeout=300s \
		https://github.com/istio-ecosystem/sail-operator/releases/download/$(SAIL_VERSION)/sail-operator-$(SAIL_VERSION).tgz

	kubectl apply -n $(ISTIO_NS) -f $(ISTIO_CONFIG_DIR)/istio.yaml
	kubectl label namespace $(ISTIO_NS) istio-discovery=enabled
	kubectl create ns $(CNI_NS)
	kubectl apply -n $(CNI_NS) -f $(ISTIO_CONFIG_DIR)/cni.yaml
	make enable-mtls

.PHONY: install-dependencies
install-dependencies:
	@echo "Installing Kuadrant dependencies..."
	@echo "Installing Gateway API..."
	kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.0" | kubectl apply -f -
	make install-metallb
	make install-cert-manager
	make install-istio

.PHONY: install-kuadrant
install-kuadrant:
	@echo "Installing Kuadrant operator..."
	helm install \
		kuadrant-operator kuadrant/kuadrant-operator \
		--create-namespace \
		--namespace $(KUADRANT_NS)
	kubectl apply -n $(KUADRANT_NS) -f $(KUADRANT_CONFIG_DIR)/kuadrant.yaml
	@echo "Kuadrant operator installed successfully"

.PHONY: install-cluster-a
install-cluster-a:
	@echo "Setting up cluster A..."
	@echo "Switching to cluster A context..."
	kubectl config use-context kind-cluster-a
	#make install-dependencies
	#make install-kuadrant
	@echo "Cluster A successfully setup"

.PHONY: install-cluster-b
install-cluster-b:
	@echo "Setting up cluster B..."
	@echo "Switching to cluster B context..."
	kubectl config use-context kind-cluster-b
	make install-dependencies
	make install-kuadrant
	@echo "Cluster B successfully setup"

.PHONY: install
install: helm-kuadrant-repo install-cluster-a #install-cluster-b
	make install-dependencies
	make install-ingress-gateway
	make install-kuadrant
	make install-echo-api
	make install-mesh-curl-client
	make install-no-mesh-curl-client

.PHONY: install-ingress-gateway
install-ingress-gateway:
	@echo "Installing Ingress Gateway..."
	kubectl create namespace $(INGRESS_GATEWAY_NS) || true
	kubectl label namespace $(INGRESS_GATEWAY_NS) istio-discovery=enabled
	kubectl apply -n $(INGRESS_GATEWAY_NS) -f config/istio/gateway/gateway.yaml

.PHONY: install-echo-api
install-echo-api:
	@echo "Installing echo api..."
	kubectl create namespace $(MESH_APP_NS)
	kubectl label namespace $(MESH_APP_NS) istio-discovery=enabled istio-injection=enabled
	kubectl apply -n $(MESH_APP_NS) -f config/apps/echo.yaml
	kubectl apply -n $(MESH_APP_NS) -f config/apps/echo-route.yaml

.PHONY: install-mesh-curl-client
install-mesh-curl-client:
	@echo "Installing curl client application..."
	kubectl create namespace $(MESH_CLIENT_NS) || true
	kubectl label namespace $(MESH_CLIENT_NS) istio-discovery=enabled istio-injection=enabled
	kubectl apply -n $(MESH_CLIENT_NS) -f config/apps/curl-client.yaml
	@echo "Curl client installed in namespace: $(MESH_CLIENT_NS)"

.PHONY: install-no-mesh-curl-client
install-no-mesh-curl-client:
	@echo "Installing curl client application..."
	kubectl create namespace $(NO_MESH_CLIENT_NS) || true
	kubectl apply -n $(NO_MESH_CLIENT_NS) -f config/apps/curl-client.yaml
	@echo "Curl client installed in namespace: $(NO_MESH_CLIENT_NS)"


.PHONY: enable-mtls
enable-mtls:
	@echo "Enabling STRICT mTLS in the mesh..."
	kubectl apply -n $(ISTIO_NS) -f config/istio/mtls/peerauthentication.yaml
	@echo "mTLS enabled successfully"

.PHONY: mtls-mode-strict
mtls-mode-strict:
	@echo "Setting PeerAuthentication mTLS mode to STRICT"
	kubectl patch peerauthentication default -n $(ISTIO_NS) --type=merge --patch '{"spec": {"mtls": {"mode": "STRICT"}}}'

.PHONY: mtls-mode-permissive
mtls-mode-permissive:
	@echo "Setting PeerAuthentication mTLS mode to PERMISSIVE"
	kubectl patch peerauthentication default -n $(ISTIO_NS) --type=merge --patch '{"spec": {"mtls": {"mode": "PERMISSIVE"}}}'

.PHONY: test-mtls
test-mtls:
	@echo "Testing mTLS via Istio sidecar communication from mesh curl-client to echo-api..."
	@echo ""
	@echo "mTLS mode set to..."
	kubectl -n istio-system get peerauthentication -o yaml | yq .items.0.spec.mtls.mode
	@echo "=== Test 1: Direct service within the mesh call ==="
	kubectl exec -n $(MESH_CLIENT_NS) deploy/curl-client -- curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | jq '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/'
	@echo "=== Test 2: Direct service outside the mesh call ==="
	kubectl exec -n $(NO_MESH_CLIENT_NS) deploy/curl-client -- curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | jq '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]'

.PHONY: setup-example-1
setup-example-1: create-cluster-a install
	kubectl -n $(KUADRANT_NS) wait --timeout=240s --for=condition=Available deployments --all
	kubectl -n $(MESH_APP_NS) wait --timeout=240s --for=condition=Available deployments --all
	@echo "Setup successfully finished"
