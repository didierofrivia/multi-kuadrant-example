# Top-level Makefile - Orchestrates examples

.PHONY: help
help:
	@echo "Multi-Cluster App Security with Kuadrant"
	@echo ""
	@echo "Available Examples:"
	@echo "  setup-example-1            - Single cluster, single mesh with custom certificates"
	@echo "  setup-example-2            - Single cluster, dual mesh with shared certificates"
	@echo ""
	@echo "Cluster Management:"
	@echo "  create-cluster-a     - Create kind cluster A"
	@echo "  delete-cluster-a     - Delete kind cluster A"
	@echo "  clean                - Delete all clusters"
	@echo ""

# Cluster management targets (shared across examples)
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

.PHONY: delete-cluster-a
delete-cluster-a:
	@echo "Deleting cluster A..."
	kind delete cluster --name cluster-a

.PHONY: delete-cluster-b
delete-cluster-b:
	@echo "Deleting cluster B..."
	kind delete cluster --name cluster-b

.PHONY: clean
clean: delete-cluster-a
	@echo "Clusters deleted"

# Example runners
.PHONY: setup-example-1
setup-example-1: create-cluster-a
	@echo "======================================"
	@echo "Running Example 1: Single Cluster, Single Mesh"
	@echo "======================================"
	@echo ""
	cd examples/single-cluster-single-mesh && $(MAKE) setup
	@echo ""
	@echo "======================================"
	@echo "Example 1 complete!"
	@echo "======================================"
	@echo ""
	@echo "Test with: cd examples/single-cluster-single-mesh && make test-mtls"

.PHONY: setup-example-2
setup-example-2: create-cluster-a
	@echo "======================================"
	@echo "Running Example 2: Single Cluster, Dual Mesh"
	@echo "======================================"
	@echo ""
	cd examples/single-cluster-dual-mesh && $(MAKE) setup
	@echo ""
	@echo "======================================"
	@echo "Example 2 complete!"
	@echo "======================================"
	@echo ""
	@echo "Test with: cd examples/single-cluster-dual-mesh && make test-cross-mesh"
