#!/usr/bin/env bash
set -euo pipefail

# ===============================
# CONFIG
# ===============================
if [ -f "../.env" ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo ".env not found. Using defaults."
  CLUSTER_NAME="bonus"
  REGISTRY_NAME="local-registry"
fi

echo "=== FULL CLEANUP START ==="

# ===============================
# FORCE DELETE ALL NAMESPACES
# ===============================
for ns in argocd gitlab dev; do
  if kubectl get ns $ns &>/dev/null; then
    echo "Force deleting namespace $ns..."

    # Remove finalizers that might block deletion
    kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

    # Delete namespace
    kubectl delete ns $ns --wait=false 2>/dev/null || true

    # Force remove if stuck
    kubectl get namespace $ns -o json | \
      jq '.spec.finalizers = []' | \
      curl -X PUT http://localhost:8001/api/v1/namespaces/$ns/finalize -H "Content-Type: application/json" --data @- 2>/dev/null || true
  fi
done

# ===============================
# DELETE CLUSTER (FORCE)
# ===============================
if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
  echo "Force deleting k3d cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

# ===============================
# REMOVE REGISTRY COMPLETELY
# ===============================
if docker ps -a --format '{{.Names}}' | grep -q "k3d-${REGISTRY_NAME}"; then
  echo "Removing local registry container..."
  docker rm -f "k3d-${REGISTRY_NAME}" || true
fi

# ===============================
# CLEAN DOCKER ARTIFACTS
# ===============================
echo "Cleaning Docker artifacts..."

# Remove any leftover k3d containers
docker ps -a --format '{{.Names}}' | grep "k3d" | xargs -r docker rm -f

# Remove unused volumes
docker volume ls -q | grep "k3d" | xargs -r docker volume rm

# Remove the k3d network
docker network ls --format '{{.Name}}' | grep "k3d" | xargs -r docker network rm 2>/dev/null || true

# ===============================
# CLEAN KUBECONFIG
# ===============================
echo "Cleaning kubeconfig..."

# Remove k3d context from kubeconfig
kubectl config unset "contexts/k3d-${CLUSTER_NAME}" 2>/dev/null || true
kubectl config unset "clusters/k3d-${CLUSTER_NAME}" 2>/dev/null || true
kubectl config unset "users/k3d-${CLUSTER_NAME}" 2>/dev/null || true

# Switch to default context if current is the deleted one
if [ "$(kubectl config current-context 2>/dev/null)" == "k3d-${CLUSTER_NAME}" ]; then
  kubectl config use-context docker-desktop 2>/dev/null || \
  kubectl config use-context minikube 2>/dev/null || \
  kubectl config unset current-context
fi

# ===============================
# REMOVE TEMP FILES
# ===============================
echo "Cleaning temporary files..."
rm -rf /tmp/github-repo /tmp/gitlab-repo /tmp/iot-repo 2>/dev/null || true

# ===============================
# VERIFY CLEANUP
# ===============================
echo ""
echo "=== VERIFICATION ==="

echo -n "Clusters: "
k3d cluster list | grep -c "${CLUSTER_NAME}" || echo "0"

echo -n "Containers: "
docker ps -a | grep -c "k3d" || echo "0"

echo -n "Volumes: "
docker volume ls | grep -c "k3d" || echo "0"

echo -n "Kube contexts: "
kubectl config get-contexts | grep -c "k3d" || echo "0"

echo "=== FULL CLEANUP COMPLETE ==="
