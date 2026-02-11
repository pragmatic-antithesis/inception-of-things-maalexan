#!/usr/bin/env bash
set -euo pipefail

# ===============================
# CONFIG
# ===============================
if [ -f "../.env" ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo ".env not found. Cannot determine cluster name."
  exit 1
fi

echo "=== CLEANUP START ==="

# ===============================
# ARGO CD
# ===============================
if kubectl get ns argocd &>/dev/null; then
  echo "Removing Argo CD namespace..."
  kubectl delete ns argocd --wait=true || true
else
  echo "ArgoCD namespace not present"
fi

# ===============================
# GITLAB (Helm Release)
# ===============================
if helm list -n gitlab 2>/dev/null | grep -q gitlab; then
  echo "Uninstalling GitLab Helm release..."
  helm uninstall gitlab -n gitlab
else
  echo "GitLab Helm release not installed"
fi

if kubectl get ns gitlab &>/dev/null; then
  echo "Deleting gitlab namespace..."
  kubectl delete ns gitlab --wait=true || true
else
  echo "Gitlab namespace not present"
fi

# ===============================
# DEV NAMESPACE
# ===============================
if kubectl get ns dev &>/dev/null; then
  echo "Deleting dev namespace..."
  kubectl delete ns dev --wait=true || true
else
  echo "Dev namespace not present"
fi

# ===============================
# DELETE K3D CLUSTER
# ===============================
if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
  echo "Deleting k3d cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}"
else
  echo "Cluster ${CLUSTER_NAME} does not exist"
fi

# ===============================
# STOP REGISTRY (BUT DO NOT DELETE)
# ===============================
if docker ps -a --format '{{.Names}}' | grep -q "k3d-${REGISTRY_NAME}"; then
  echo "Stopping local registry container..."
  docker stop "k3d-${REGISTRY_NAME}" || true
else
  echo "Registry container not running"
fi

echo "=== CLEANUP COMPLETE ==="
