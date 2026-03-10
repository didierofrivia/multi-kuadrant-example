SAIL_VERSION = 1.28.3
ISTIO_NS = istio-system
ISTIO_NS_2 = istio-system-2
CNI_NS = istio-cni
ISTIO_CONFIG_DIR = config/istio

MESH_APP_NS = mesh-demo-apps
MESH_APP_NS_2 = mesh-demo-apps-2
MESH_CLIENT_NS = mesh-client-apps
MESH_CLIENT_NS_2 = mesh-client-apps-2

CERT_MANAGER_CONFIG_DIR = config/cert-manager
SCRIPTS_DIR = scripts

# Gateway and Kuadrant
INGRESS_GATEWAY_NS = ingress-gateways
KUADRANT_NS = kuadrant-system
KUADRANT_CONFIG_DIR = config/kuadrant

.PHONY: help
help:
	@echo "Example 2: Single Cluster, Dual Mesh"
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "Complete Setup:"
	@echo "  setup                  - Complete dual-mesh installation (cluster + dependencies + both meshes + cross-mesh config)"
	@echo ""
	@echo "Cluster Management:"
	@echo "  create-cluster-a       - Create kind cluster A"
	@echo "  delete-cluster-a       - Delete kind cluster A"
	@echo "  clean                  - Delete cluster and all resources"
	@echo ""
	@echo "Infrastructure Installation:"
	@echo "  install-dependencies   - Install Gateway API, MetalLB, cert-manager"
	@echo "  install-metallb        - Install MetalLB load balancer"
	@echo "  install-cert-manager   - Install cert-manager"
	@echo "  install-cni            - Install Istio CNI"
	@echo ""
	@echo "Mesh Installation:"
	@echo "  setup-mesh-1           - Install mesh-1 control plane + apps + wait for ready"
	@echo "  setup-mesh-2           - Install mesh-2 control plane + apps + wait for ready"
	@echo "  install-mesh-1         - Install mesh-1 control plane only"
	@echo "  install-mesh-2         - Install mesh-2 control plane only"
	@echo ""
	@echo "Application Installation:"
	@echo "  install-apps           - Install demo apps in both meshes"
	@echo "  install-apps-mesh-1    - Install echo-api and curl-client in mesh-1"
	@echo "  install-apps-mesh-2    - Install echo-api-2 and curl-client in mesh-2"
	@echo ""
	@echo "Cross-Mesh Configuration:"
	@echo "  configure-cross-mesh   - Apply ServiceEntries for cross-mesh communication"
	@echo ""
	@echo "Certificate Management:"
	@echo "  setup-custom-ca        - Setup root CA in istio-system"
	@echo "  setup-custom-ca-mesh-2 - Copy root CA to istio-system-2"
	@echo ""
	@echo "Testing:"
	@echo "  test-mtls              - Test intra-mesh mTLS (mesh-1 → mesh-1, mesh-2 → mesh-2)"
	@echo "  test-cross-mesh        - Test cross-mesh communication (all 4 scenarios)"
	@echo ""
	@echo "Kuadrant (Optional):"
	@echo "  setup-kuadrant         - Install Kuadrant + gateway + routes + policies"
	@echo "  setup-with-kuadrant    - Complete setup including Kuadrant"
	@echo "  install-kuadrant       - Install Kuadrant operator only"
	@echo "  install-gateway        - Install ingress gateway"
	@echo "  install-routes         - Install HTTPRoutes for both meshes"
	@echo "  install-policies       - Install TLS, Auth, and RateLimit policies"
	@echo "  restart-mesh-1-istiod  - Restart mesh-1 Istiod (for discovery changes)"
	@echo "  test-auth              - Test API key authentication (mesh-1)"
	@echo "  test-ratelimit         - Test rate limiting (mesh-1)"
	@echo "  test-unprotected       - Test unprotected access (mesh-2)"
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup             # Install dual mesh with demo apps (basic - no ingress protection)"
	@echo "  make setup-with-kuadrant  # Install with Kuadrant policies (complete - ingress protection)"
	@echo "  make test-cross-mesh   # Verify cross-mesh mTLS works"

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
	@echo "Cluster deleted"

.PHONY: install-dependencies
install-dependencies:
	@echo "Installing dependencies..."
	@echo "Installing Gateway API..."
	kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.0" | kubectl apply -f -
	make install-metallb
	make install-cert-manager

.PHONY: install-metallb
install-metallb:
	@echo "Installing MetalLB..."
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
	helm install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version v1.15.3 \
		--set crds.enabled=true

.PHONY: install-cni
install-cni:
	@echo "Installing Istio CNI..."
	kubectl create namespace $(CNI_NS) || true
	kubectl apply -n $(CNI_NS) -f $(ISTIO_CONFIG_DIR)/cni.yaml

.PHONY: setup-custom-ca
setup-custom-ca:
	@echo "Setting up custom CA for mesh-1..."
	kubectl create namespace $(ISTIO_NS) || true
	kubectl apply -f $(CERT_MANAGER_CONFIG_DIR)/root-ca.yaml
	@echo "Waiting for certificate to be ready..."
	kubectl wait --for=condition=Ready certificate/istio-root-ca -n $(ISTIO_NS) --timeout=300s
	$(SCRIPTS_DIR)/create-istio-cacerts.sh $(ISTIO_NS)

.PHONY: setup-custom-ca-mesh-2
setup-custom-ca-mesh-2:
	@echo "Setting up custom CA for mesh-2 (copying from mesh-1)..."
	kubectl create namespace $(ISTIO_NS_2) || true
	$(SCRIPTS_DIR)/create-istio-cacerts.sh $(ISTIO_NS_2)

.PHONY: install-mesh-1
install-mesh-1:
	@echo "======================================"
	@echo "Installing Mesh-1 (istio-system)"
	@echo "======================================"
	make setup-custom-ca
	@echo "Installing Sail Operator..."
	helm install sail-operator \
		--namespace $(ISTIO_NS) \
		--wait \
		--timeout=300s \
		https://github.com/istio-ecosystem/sail-operator/releases/download/$(SAIL_VERSION)/sail-operator-$(SAIL_VERSION).tgz
	@echo "Applying Istio CR for mesh-1..."
	kubectl apply -n $(ISTIO_NS) -f $(ISTIO_CONFIG_DIR)/istio-mesh-1.yaml
	@echo "Labeling namespace for mesh-1 discovery..."
	kubectl label namespace $(ISTIO_NS) istio-discovery=enabled mesh=mesh-1 --overwrite
	make install-cni
	@echo "Enabling mTLS for mesh-1..."
	kubectl apply -n $(ISTIO_NS) -f $(ISTIO_CONFIG_DIR)/mtls/peerauthentication-mesh-1.yaml
	@echo "Mesh-1 installation complete!"

.PHONY: install-mesh-2
install-mesh-2: setup-custom-ca-mesh-2
	@echo "======================================"
	@echo "Installing Mesh-2 (istio-system-2)"
	@echo "======================================"
	@echo "Applying Istio CR for mesh-2..."
	kubectl apply -n $(ISTIO_NS_2) -f $(ISTIO_CONFIG_DIR)/istio-mesh-2.yaml
	@echo "Labeling namespace for mesh-2 discovery..."
	kubectl label namespace $(ISTIO_NS_2) istio-discovery=enabled mesh=mesh-2 --overwrite
	@echo "Enabling mTLS for mesh-2..."
	kubectl apply -n $(ISTIO_NS_2) -f $(ISTIO_CONFIG_DIR)/mtls/peerauthentication-mesh-2.yaml
	@echo "Mesh-2 installation complete!"

.PHONY: install-apps-mesh-1
install-apps-mesh-1:
	@echo "Installing applications in mesh-1..."
	kubectl create namespace $(MESH_APP_NS) || true
	kubectl label namespace $(MESH_APP_NS) istio-discovery=enabled istio.io/rev=default mesh=mesh-1 --overwrite
	kubectl apply -n $(MESH_APP_NS) -f config/apps/echo-mesh-1.yaml

	kubectl create namespace $(MESH_CLIENT_NS) || true
	kubectl label namespace $(MESH_CLIENT_NS) istio-discovery=enabled istio.io/rev=default mesh=mesh-1 --overwrite
	kubectl apply -n $(MESH_CLIENT_NS) -f config/apps/curl-client-mesh-1.yaml
	@echo "Mesh-1 applications installed!"

.PHONY: install-apps-mesh-2
install-apps-mesh-2:
	@echo "Installing applications in mesh-2..."
	kubectl create namespace $(MESH_APP_NS_2) || true
	kubectl label namespace $(MESH_APP_NS_2) istio-discovery=enabled istio.io/rev=default-2 mesh=mesh-2 --overwrite
	kubectl apply -n $(MESH_APP_NS_2) -f config/apps/echo-mesh-2.yaml

	kubectl create namespace $(MESH_CLIENT_NS_2) || true
	kubectl label namespace $(MESH_CLIENT_NS_2) istio-discovery=enabled istio.io/rev=default-2 mesh=mesh-2 --overwrite
	kubectl apply -n $(MESH_CLIENT_NS_2) -f config/apps/curl-client-mesh-2.yaml
	@echo "Mesh-2 applications installed!"

.PHONY: setup-mesh-1
setup-mesh-1: install-mesh-1 install-apps-mesh-1
	@echo ""
	@echo "Waiting for deployments to be ready..."
	@echo "Waiting for mesh-1 applications..."
	kubectl -n $(MESH_APP_NS) wait --timeout=240s --for=condition=Available deployments --all
	kubectl -n $(MESH_CLIENT_NS) wait --timeout=240s --for=condition=Available deployments --all

.PHONY: setup-mesh-2
setup-mesh-2: install-mesh-2 install-apps-mesh-2
	@echo "Waiting for mesh-2 applications..."
	kubectl -n $(MESH_APP_NS_2) wait --timeout=240s --for=condition=Available deployments --all
	kubectl -n $(MESH_CLIENT_NS_2) wait --timeout=240s --for=condition=Available deployments --all

.PHONY: configure-cross-mesh
  configure-cross-mesh:
	@echo "Configuring cross-mesh service discovery..."
	kubectl apply -f config/apps/serviceentry-mesh-2-to-mesh-1.yaml
	kubectl apply -f config/apps/serviceentry-mesh-1-to-mesh-2.yaml
	@echo "Cross-mesh configuration applied!"

.PHONY: setup
setup: create-cluster-a install-dependencies setup-mesh-1 setup-mesh-2 configure-cross-mesh
	@echo ""
	@echo "======================================"
	@echo "Dual-mesh installation complete!"
	@echo "======================================"
	@echo ""
	@echo "Test cross-mesh communication: make test-cross-mesh"
	@echo "Test intra-mesh mTLS: make test-mtls"

.PHONY: test-mtls
test-mtls:
	@echo "Testing mTLS within each mesh..."
	@echo ""
	@echo "=== Mesh-1 mTLS Test ==="
	@echo "Current mTLS mode (mesh-1):"
	kubectl -n $(ISTIO_NS) get peerauthentication default -o yaml | yq .spec.mtls.mode
	@echo ""
	kubectl exec -n $(MESH_CLIENT_NS) deploy/curl-client -- \
		curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | \
		jq '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/'
	@echo ""
	@echo "=== Mesh-2 mTLS Test ==="
	@echo "Current mTLS mode (mesh-2):"
	kubectl -n $(ISTIO_NS_2) get peerauthentication default -o yaml | yq .spec.mtls.mode
	@echo ""
	kubectl exec -n $(MESH_CLIENT_NS_2) deploy/curl-client -- \
		curl -s http://echo-api-2.$(MESH_APP_NS_2).svc.cluster.local:3000/echo | \
		jq '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/'

.PHONY: test-cross-mesh
test-cross-mesh:
	@echo "======================================"
	@echo "Testing Cross-Mesh Communication"
	@echo "======================================"
	@echo ""
	@echo "=== Test 1: Mesh-1 → Mesh-1 (intra-mesh) ==="
	@echo "Client: mesh-client-apps → Server: mesh-demo-apps"
	kubectl exec -n $(MESH_CLIENT_NS) deploy/curl-client -- \
		curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | \
		jq -r '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/' || echo "Request failed"
	@echo ""
	@echo "=== Test 2: Mesh-2 → Mesh-2 (intra-mesh) ==="
	@echo "Client: mesh-client-apps-2 → Server: mesh-demo-apps-2"
	kubectl exec -n $(MESH_CLIENT_NS_2) deploy/curl-client -- \
		curl -s http://echo-api-2.$(MESH_APP_NS_2).svc.cluster.local:3000/echo | \
		jq -r '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/' || echo "Request failed"
	@echo ""
	@echo "=== Test 3: Mesh-1 → Mesh-2 (cross-mesh) ==="
	@echo "Client: mesh-client-apps (mesh-1) → Server: mesh-demo-apps-2 (mesh-2)"
	kubectl exec -n $(MESH_CLIENT_NS) deploy/curl-client -- \
		curl -s http://echo-api-2.$(MESH_APP_NS_2).svc.cluster.local:3000/echo | \
		jq -r '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/' || echo "Request failed"
	@echo ""
	@echo "=== Test 4: Mesh-2 → Mesh-1 (cross-mesh) ==="
	@echo "Client: mesh-client-apps-2 (mesh-2) → Server: mesh-demo-apps (mesh-1)"
	kubectl exec -n $(MESH_CLIENT_NS_2) deploy/curl-client -- \
		curl -s http://echo-api.$(MESH_APP_NS).svc.cluster.local:3000/echo | \
		jq -r '.headers["HTTP_X_FORWARDED_CLIENT_CERT"]' | sed 's/Hash=[a-z0-9]*;/Hash=<redacted>;/' || echo "Request failed"
	@echo ""
	@echo "======================================"
	@echo "Cross-mesh testing complete!"
	@echo "======================================"

# Kuadrant Targets
.PHONY: install-kuadrant
install-kuadrant:
	@echo "Installing Kuadrant operator..."
	helm repo add kuadrant https://kuadrant.io/helm-charts/ --force-update
	helm install kuadrant-operator kuadrant/kuadrant-operator \
		--create-namespace \
		--namespace $(KUADRANT_NS)
	kubectl label namespace $(KUADRANT_NS) istio-discovery=enabled istio.io/rev=default mesh=mesh-1
	kubectl apply -n $(KUADRANT_NS) -f $(KUADRANT_CONFIG_DIR)/kuadrant.yaml
	@echo "Kuadrant operator installed successfully"

.PHONY: install-gateway
install-gateway:
	@echo "Installing Ingress Gateway..."
	kubectl create namespace $(INGRESS_GATEWAY_NS) || true
	kubectl label namespace $(INGRESS_GATEWAY_NS) istio-discovery=enabled mesh=mesh-1 --overwrite
	kubectl apply -n $(INGRESS_GATEWAY_NS) -f $(KUADRANT_CONFIG_DIR)/gateway.yaml
	@echo "Gateway installed"

.PHONY: setup-gateway-tls
setup-gateway-tls:
	@echo "Setting up TLS for gateway..."
	kubectl apply -f $(CERT_MANAGER_CONFIG_DIR)/ingress-issuer.yaml
	kubectl apply -n $(INGRESS_GATEWAY_NS) -f $(KUADRANT_CONFIG_DIR)/tlspolicy.yaml
	@echo "TLSPolicy applied"

.PHONY: install-routes
install-routes:
	@echo "Installing HTTPRoutes in app namespaces..."
	kubectl apply -n $(MESH_APP_NS) -f config/apps/echo-route.yaml
	kubectl apply -n $(MESH_APP_NS_2) -f config/apps/echo-route-2.yaml
	@echo "HTTPRoutes and ServiceEntry installed"

.PHONY: install-auth
install-auth:
	@echo "Installing AuthPolicy (mesh-1 /echo only)..."
	kubectl apply -f $(KUADRANT_CONFIG_DIR)/authpolicy.yaml
	@echo "AuthPolicy applied"
	@echo "API Key: secret-api-key-12345"

.PHONY: install-ratelimit
install-ratelimit:
	@echo "Installing RateLimitPolicy (mesh-1 /echo only)..."
	kubectl apply -n $(MESH_APP_NS) -f $(KUADRANT_CONFIG_DIR)/ratelimitpolicy.yaml
	@echo "RateLimitPolicy applied"

.PHONY: install-policies
install-policies: setup-gateway-tls install-auth install-ratelimit
	@echo "All Kuadrant policies installed"

.PHONY: get-gateway-ip
get-gateway-ip:
	@echo "Gateway IP:"
	@kubectl get gateway/kuadrant-ingressgateway -n $(INGRESS_GATEWAY_NS) \
		-o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "Not ready"

.PHONY: test-auth
test-auth:
	@echo "Testing API key authentication on /echo (mesh-1)..."
	@export INGRESS_IP=$$(kubectl get gateway/kuadrant-ingressgateway -n $(INGRESS_GATEWAY_NS) \
		-o jsonpath='{.status.addresses[0].value}'); \
	echo ""; \
	echo "=== Test 1: Request to /echo without API key (should fail with 401) ==="; \
	curl -k https://demo.$$INGRESS_IP.nip.io/echo -w "\nHTTP Status: %{http_code}\n" -o /dev/null 2>/dev/null || true; \
	echo ""; \
	echo "=== Test 2: Request to /echo with valid API key (should succeed) ==="; \
	curl -k -H "Authorization: Bearer secret-api-key-12345" \
		https://demo.$$INGRESS_IP.nip.io/echo 2>/dev/null | jq '.path, .headers["HTTP_X_AUTH_DATA"]' || true; \
	echo ""; \
	echo "=== Test 3: Request to /echo with invalid API key (should fail with 401) ==="; \
	curl -k -H "Authorization: Bearer wrong-key" \
		https://demo.$$INGRESS_IP.nip.io/echo -w "\nHTTP Status: %{http_code}\n" -o /dev/null 2>/dev/null || true

.PHONY: test-ratelimit
test-ratelimit:
	@echo "Testing Rate Limiting on /echo (mesh-1) - 5 requests per 10 seconds..."
	@export INGRESS_IP=$$(kubectl get gateway/kuadrant-ingressgateway -n $(INGRESS_GATEWAY_NS) \
		-o jsonpath='{.status.addresses[0].value}'); \
	echo ""; \
	for i in $$(seq 1 10); do \
		echo -n "Request $$i: "; \
		curl -k -s -H "Authorization: Bearer secret-api-key-12345" \
			-w "HTTP %{http_code}\n" https://demo.$$INGRESS_IP.nip.io/echo -o /dev/null 2>/dev/null; \
		sleep 0.5; \
	done; \
	echo ""; \
	echo "Expected: First 5 requests = 200, remaining = 429"

.PHONY: test-unprotected
test-unprotected:
	@echo "Testing unprotected access to /echo2 (mesh-2)..."
	@export INGRESS_IP=$$(kubectl get gateway/kuadrant-ingressgateway -n $(INGRESS_GATEWAY_NS) \
		-o jsonpath='{.status.addresses[0].value}'); \
	echo ""; \
	echo "=== Test 1: Access /echo2 without API key (should succeed) ==="; \
	curl -k https://demo.$$INGRESS_IP.nip.io/echo2 2>/dev/null | jq '.path' || echo "Request failed"; \
	echo ""; \
	echo "=== Test 2: Rapid requests to /echo2 (no rate limit) ==="; \
	for i in $$(seq 1 10); do \
		echo -n "Request $$i: "; \
		curl -k -s -w "HTTP %{http_code}\n" \
			https://demo.$$INGRESS_IP.nip.io/echo2 -o /dev/null 2>/dev/null; \
		sleep 0.2; \
	done; \
	echo ""; \
	echo "Expected: All requests = 200 (no auth, no rate limit)"

.PHONY: setup-kuadrant
setup-kuadrant: install-kuadrant install-gateway install-routes install-policies
	@echo "Waiting for Kuadrant components to be ready..."
	kubectl -n $(KUADRANT_NS) wait --timeout=240s --for=condition=Available deployments --all
	@echo "Waiting for gateway to get IP address..."
	kubectl wait --timeout=120s --for=jsonpath='{.status.addresses[0].value}' \
		gateway/kuadrant-ingressgateway -n $(INGRESS_GATEWAY_NS) 2>/dev/null || true
	@echo ""
	@echo "======================================"
	@echo "Kuadrant setup complete!"
	@echo "======================================"
	@make get-gateway-ip

.PHONY: setup-with-kuadrant
setup-with-kuadrant: setup setup-kuadrant
	@echo ""
	@echo "======================================"
	@echo "Dual-mesh with Kuadrant complete!"
	@echo "======================================"
	@echo ""
	@echo "Test protected route (mesh-1):"
	@echo "  make test-auth"
	@echo "  make test-ratelimit"
	@echo ""
	@echo "Test unprotected route (mesh-2):"
	@echo "  make test-unprotected"
	@echo ""
	@echo "Compare both routes:"
	@echo "  make test-policy-comparison"
