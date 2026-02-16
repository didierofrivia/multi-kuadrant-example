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
create-clusters: create-cluster-a create-cluster-b
	@echo "Both clusters created successfully"

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

.PHONY: install-istio
install-istio:
	@echo "Installing Istio through sail operator..."
	helm install sail-operator \
		--create-namespace \
		--namespace istio-system \
		--wait \
		--timeout=300s \
		https://github.com/istio-ecosystem/sail-operator/releases/download/0.1.0/sail-operator-0.1.0.tgz

	kubectl apply -f -<<EOF
    apiVersion: sailoperator.io/v1alpha1
    kind: Istio
    metadata:
   	  name: default
    spec:
      # Supported values for sail-operator v0.1.0 are [v1.22.4,v1.23.0]
      version: v1.23.0
      namespace: istio-system
      # Disable autoscaling to reduce dev resources
      values:
        pilot:
          autoscaleEnabled: false
	EOF

.PHONY: install-dependencies
install-dependencies:
	@echo "Installing Kuadrant dependencies..."
	@echo "Installing Gateway API..."
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
	make install-cert-manager
	make install-istio

.PHONY: install-kuadrant
install-kuadrant:
	@echo "Installing Kuadrant operator..."
	helm install \
		kuadrant-operator kuadrant/kuadrant-operator \
		--create-namespace \
		--namespace kuadrant-system
	@echo "Kuadrant operator installed successfully"

.PHONY: install-cluster-a
install-cluster-a:
	@echo "Setting up cluster A..."
	@echo "Switching to cluster A context..."
	kubectl config use-context kind-cluster-a
	make install-dependencies
	make install-kuadrant
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
install: helm-kuadrant-repo install-cluster-a install-cluster-b
	@echo "Kuadrant operator installed in both clusters"

.PHONY: setup
setup: create-clusters install
