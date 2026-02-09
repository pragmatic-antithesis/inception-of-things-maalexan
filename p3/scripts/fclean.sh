#!/bin/bash
set -euo pipefail

# ===============================
# CONFIGS
# ===============================
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo ".env not found! Aborting."
  exit 1
fi

# ===============================
# HELPERS
# ===============================
function safe_delete_ns {
  local ns=$1
  if kubectl get ns "$ns" &> /dev/null; then
    echo "Deleting namespace $ns..."
    kubectl delete ns "$ns" --ignore-not-found
  else
    echo "Namespace $ns doesn't exist, ignored."
  fi
}

# ===============================
# STOP CLUSTER
# ===============================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Stopping k3d cluster $CLUSTER_NAME..."
  k3d cluster stop "$CLUSTER_NAME"
else
  echo "Cluster $CLUSTER_NAME inexistant."
fi

# ===============================
# DELETE CLUSTER
# ===============================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Removing k3d cluster $CLUSTER_NAME..."
  k3d cluster delete "$CLUSTER_NAME"
else
  echo "Cluster $CLUSTER_NAME inexistant"
fi

# ===============================
# REMOVE NAMESPACES (optional)
# ===============================
for ns in "$ARGOCD_NAMESPACE" "$DEV_NAMESPACE"; do
  safe_delete_ns "$ns"
done

# ===============================
# CLEAN KUBECTL CONTEXTS
# ===============================
echo "Cleaning kubectl old contexts..."
kubectl config delete-context "$CLUSTER_NAME" &> /dev/null || true
kubectl config unset users."$CLUSTER_NAME-admin" &> /dev/null || true
kubectl config unset clusters."$CLUSTER_NAME" &> /dev/null || true

echo "=== Teardown done! Everything safely removed ==="
