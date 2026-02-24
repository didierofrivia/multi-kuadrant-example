APP_DEVELOPER_NS ?= demo
KUADRANT_GATEWAY_NS ?= ingress-gateways
INGRESS_IP ?= 10.89.0.0

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  create-cluster-a   - Create kind cluster A (ports 8080/8443)"
	@echo "  create-cluster-b   - Create kind cluster B (ports 9080/9443)"
	@echo "  create-clusters    - Create both clusters"
	@echo "  delete-cluster-a   - Delete kind cluster A"
	@echo "  delete-cluster-b   - Delete kind cluster B"
	@echo "  delete-clusters    - Delete both clusters"
	@echo "  clean              - Delete both clusters (alias)"
	@echo "  install-cluster-a 	- Install Kuadrant operator in cluster A"
	@echo "  install-cluster-b 	- Install Kuadrant operator in cluster B"
	@echo "  install   			- Install Kuadrant operator in both clusters"

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

SAIL_VERSION = 1.28.3
ISTIO_NS = istio-system
CNI_NS = istio-cni
ISTIO_CONFIG_DIR = config/istio
.PHONY: install-istio
install-istio:
	@echo "Installing Istio through sail operator..."
	helm install sail-operator \
		--create-namespace \
		--namespace $(ISTIO_NS) \
		--wait \
		--timeout=300s \
		https://github.com/istio-ecosystem/sail-operator/releases/download/$(SAIL_VERSION)/sail-operator-$(SAIL_VERSION).tgz

	kubectl apply -n $(ISTIO_NS) -f $(ISTIO_CONFIG_DIR)/istio.yaml
	kubectl label namespace $(ISTIO_NS) istio-discovery=enabled
	kubectl create ns $(CNI_NS)
	kubectl apply -n $(CNI_NS) -f $(ISTIO_CONFIG_DIR)/cni.yaml

.PHONY: install-dependencies
install-dependencies:
	@echo "Installing Kuadrant dependencies..."
	@echo "Installing Gateway API..."
	kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.0" | kubectl apply -f -
	make install-metallb
	make install-cert-manager
	make install-istio

KUADRANT_NS ?= kuadrant-system
KUADRANT_CONFIG_DIR = config/kuadrant
.PHONY: install-kuadrant
install-kuadrant:
	@echo "Installing Kuadrant operator..."
	helm install \
		kuadrant-operator kuadrant/kuadrant-operator \
		--create-namespace \
		--namespace $(KUADRANT_NS)
	kubectl apply -n $(KUADRANT_NS) -f $(KUADRANT_CONFIG_DIR)/kuadrant.yaml
	@echo "Kuadrant operator installed successfully"


.PHONY: install-echo-api
install-echo-api:
	@echo "Installing echo api..."
	kubectl create namespace $(APP_DEVELOPER_NS)
	kubectl label namespace $(APP_DEVELOPER_NS) istio-discovery=enabled
	kubectl apply -n $(APP_DEVELOPER_NS) -f config/apps/echo.yaml

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
	make install-kuadrant
	make install-echo-api


.PHONY: setup
setup: create-clusters install
	kubectl -n $(KUADRANT_NS) wait --timeout=240s --for=condition=Available deployments --all
	kubectl -n $(APP_DEVELOPER_NS) wait --timeout=240s --for=condition=Available deployments --all
	@echo "Setup successfully finished"