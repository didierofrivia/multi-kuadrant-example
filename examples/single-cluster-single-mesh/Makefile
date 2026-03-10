SAIL_VERSION = 1.28.3
ISTIO_NS = istio-system
CNI_NS = istio-cni
ISTIO_CONFIG_DIR = config/istio

INGRESS_GATEWAY_NAME ?= kuadrant-ingressgateway
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
	@echo "Example 1: Single Cluster, Single Mesh"
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup                # Install basic setup (no Kuadrant)"
	@echo "  make setup-with-kuadrant  # Install with Kuadrant policies"
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "Cluster Management:"
	@echo "  create-cluster-a     - Create kind cluster A"
	@echo "  delete-cluster-a     - Delete kind cluster A"
	@echo "  clean                - Delete all clusters"
	@echo ""
	@echo "Component Installation:"
	@echo "  install-dependencies  - Install Gateway API, MetalLB, cert-manager, and Istio"
	@echo "  install-metallb       - Install MetalLB load balancer"
	@echo "  install-cert-manager  - Install cert-manager"
	@echo "  install-istio         - Install Istio through sail operator"
	@echo "  install-echo-api      - Install echo API test application"
	@echo "  install-mesh-curl-client   - Install curl client in mesh namespace"
	@echo "  install-no-mesh-curl-client - Install curl client outside mesh"
	@echo "  install-ingress-gateway    - Install Istio ingress gateway"
	@echo ""
	@echo "Security Configuration:"
	@echo "  setup-custom-ca       - Create custom CA certificates for Istio"
	@echo "  clean-certificates    - Remove all certificate resources"
	@echo "  enable-mtls           - Enable (PERMISSIVE by default) mTLS in the mesh"
	@echo "  mtls-mode-strict      - Switch to STRICT mTLS mode"
	@echo "  mtls-mode-permissive  - Switch to PERMISSIVE mTLS mode"
	@echo ""
	@echo "Kuadrant Configuration:"
	@echo "  install-kuadrant      - Install Kuadrant operator and CR"
	@echo "  setup-gateway-tls     - Setup TLS certificate for gateway"
	@echo "  install-tlspolicy     - Apply TLSPolicy to gateway"
	@echo "  install-ratelimit     - Apply RateLimitPolicy to echo-api (5 req/10s)"
	@echo "  install-auth          - Apply AuthPolicy to echo-api (API key)"
	@echo "  install-policies      - Install all Kuadrant policies (TLS, RateLimit, Auth)"
	@echo "  setup-kuadrant        - Install Kuadrant + all policies"
	@echo ""
	@echo "Testing:"
	@echo "  test-mtls             - Test mTLS communication"
	@echo "  test-auth             - Test API key authentication (3 scenarios)"
	@echo "  test-ratelimit        - Test rate limiting (triggers 429 after 5 req)"
	@echo ""
	@echo "Complete Setup:"
	@echo "  setup                 - Install all components (without Kuadrant policies)"
	@echo "  setup-with-kuadrant   - Complete setup including Kuadrant and all policies"

.PHONY: create-cluster-a
create-cluster-a:
	@echo "Creating cluster A..."
	kind create cluster --config ../../kind/kind-cluster-a.yaml
	@echo "Cluster A created successfully"
	@echo "HTTP: localhost:8080"
	@echo "HTTPS: localhost:8443"

.PHONY: delete-cluster-a
delete-cluster-a:
	@echo "Deleting cluster A..."
	kind delete cluster --name cluster-a

.PHONY: clean
clean: delete-cluster-a
	@echo "Clusters deleted"

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
	@echo "Installing dependencies..."
	@echo "Installing Gateway API..."
	kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.0" | kubectl apply -f -
	make install-metallb
	make install-cert-manager
	make install-istio

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
	@echo "Installing curl client application in mesh..."
	kubectl create namespace $(MESH_CLIENT_NS) || true
	kubectl label namespace $(MESH_CLIENT_NS) istio-discovery=enabled istio-injection=enabled
	kubectl apply -n $(MESH_CLIENT_NS) -f config/apps/curl-client.yaml
	@echo "Curl client installed in namespace: $(MESH_CLIENT_NS)"

.PHONY: install-no-mesh-curl-client
install-no-mesh-curl-client:
	@echo "Installing curl client application outside mesh..."
	kubectl create namespace $(NO_MESH_CLIENT_NS) || true
	kubectl apply -n $(NO_MESH_CLIENT_NS) -f config/apps/curl-client.yaml
	@echo "Curl client installed in namespace: $(NO_MESH_CLIENT_NS)"

.PHONY: enable-mtls
enable-mtls:
	@echo "Enabling mTLS in the mesh..."
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
	@echo "Testing mTLS communication..."
	@echo ""
	@echo "Current mTLS mode:"
	kubectl -n $(ISTIO_NS) get peerauthentication -o yaml | yq .items.0.spec.mtls.mode
	@echo ""
	@echo "=== Test 1: Client within mesh → echo-api ==="
	kubectl exec -n $(MESH_CLIENT_NS) deploy/curl-client -- curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | jq '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/'
	@echo ""
	@echo "=== Test 2: Client outside mesh → echo-api ==="
	kubectl exec -n $(NO_MESH_CLIENT_NS) deploy/curl-client -- curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | jq '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]'

# Kuadrant Targets
.PHONY: install-kuadrant
install-kuadrant:
	@echo "Adding/Updating Kuadrant helm repo..."
	helm repo add kuadrant https://kuadrant.io/helm-charts/ --force-update
	@echo "Installing Kuadrant operator..."
	helm install \
		kuadrant-operator kuadrant/kuadrant-operator \
		--create-namespace \
		--namespace $(KUADRANT_NS)
	kubectl label namespace $(KUADRANT_NS) istio-discovery=enabled
	kubectl apply -n $(KUADRANT_NS) -f $(KUADRANT_CONFIG_DIR)/kuadrant.yaml
	@echo "Kuadrant operator installed successfully"

.PHONY: setup-gateway-tls
setup-gateway-tls:
	@echo "Setting up TLS certificate for gateway..."
	@echo "Creating CA issuer from root CA..."
	kubectl apply -n $(INGRESS_GATEWAY_NS) -f $(CERT_MANAGER_CONFIG_DIR)/ingress-issuer.yaml
	@echo "Configuring Ingress Gateway for HTTPS..."
	kubectl apply -n $(INGRESS_GATEWAY_NS) -f $(KUADRANT_CONFIG_DIR)/gateway.yaml
	make install-tlspolicy
	@echo "Gateway TLS certificate ready!"

.PHONY: install-tlspolicy
install-tlspolicy:
	@echo "Installing TLSPolicy..."
	kubectl apply -n $(INGRESS_GATEWAY_NS) -f $(KUADRANT_CONFIG_DIR)/tlspolicy.yaml
	@echo "TLSPolicy applied successfully"

.PHONY: install-ratelimit
install-ratelimit:
	@echo "Installing RateLimitPolicy..."
	kubectl apply -n $(MESH_APP_NS) -f $(KUADRANT_CONFIG_DIR)/ratelimitpolicy.yaml
	@echo "RateLimitPolicy applied successfully"

.PHONY: install-auth
install-auth:
	@echo "Installing AuthPolicy..."
	kubectl apply -f $(KUADRANT_CONFIG_DIR)/authpolicy.yaml
	@echo "AuthPolicy applied successfully"
	@echo ""
	@echo "API Key for testing: secret-api-key-12345"

.PHONY: install-policies
install-policies: setup-gateway-tls install-tlspolicy install-ratelimit install-auth
	@echo ""
	@echo "All Kuadrant policies installed successfully!"

.PHONY: test-auth
test-auth:
	@echo "Testing API key authentication..."
	@echo ""
	@echo ""
	@echo "=== Test 1: Request without API key (should fail with 401) ==="
	curl -k https://demo.$(INGRESS_IP).nip.io/echo -w "\nHTTP Status: %{http_code}\n" || true
	@echo ""
	@echo "=== Test 2: Request with valid API key (should succeed) ==="
	curl -k -H "Authorization: Bearer secret-api-key-12345" https://demo.$(INGRESS_IP).nip.io/echo --insecure | jq
	@echo ""
	@echo "=== Test 3: Request with invalid API key (should fail with 401) ==="
	curl -k -H "Authorization: Bearer wrong-key" https://demo.$(INGRESS_IP).nip.io/echo --insecure -w "\nHTTP Status: %{http_code}\n" || true

.PHONY: test-ratelimit
test-ratelimit:
	@echo "Testing Rate Limiting (5 requests per 10 seconds)..."
	@echo ""
	@echo "Sending requests to trigger rate limit..."
	@for i in $$(seq 1 10); do \
		echo "Request $$i:"; \
		curl -k -s -H "Authorization: Bearer secret-api-key-12345" \
			-w " - HTTP %{http_code}\n" https://demo.$(INGRESS_IP).nip.io/echo --insecure -o /dev/null; \
		sleep 0.5; \
	done
	@echo ""
	@echo "You should see some 429 (Too Many Requests) responses after request 5"

.PHONY: setup-kuadrant
setup-kuadrant: install-kuadrant install-policies
	@echo "Waiting for deployments to be ready..."
	kubectl -n $(KUADRANT_NS) wait --timeout=240s --for=condition=Available deployments --all
	@echo ""
	@echo "==================================="
	@echo "Kuadrant installation complete!"
	@echo "==================================="
	@echo ""

.PHONY: setup
setup: create-cluster-a install-dependencies install-ingress-gateway install-echo-api install-mesh-curl-client install-no-mesh-curl-client
	@echo ""
	@echo "Waiting for deployments to be ready..."
	kubectl -n $(MESH_APP_NS) wait --timeout=240s --for=condition=Available deployments --all
	@echo ""
	@echo "==================================="
	@echo "Example Single Cluster, Single Mesh installation complete!"
	@echo "==================================="
	@echo ""
	@echo "Test mTLS: make test-mtls"
	@echo ""
	@echo "Then change the Istio mTLS mode to Strict and run it again: make tls-mode-strict && make test-mtls"

.PHONY: setup-with-kuadrant
setup-with-kuadrant: setup setup-kuadrant
	@echo ""
	@echo "==================================="
	@echo "Setup complete!"
	@echo "==================================="
	@echo ""
	@echo "Test HTTPS: make test-https"
	@echo "Test Auth: make test-auth"
	@echo "Test Rate Limit: make test-ratelimit"
