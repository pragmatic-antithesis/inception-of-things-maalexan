#!/bin/bash
set -euo pipefail

# ===============================
# CONFIGURAÇÕES DO USUÁRIO
# ===============================
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo ".env não encontrado! Abortando."
  exit 1
fi

# ===============================
# FUNÇÕES AUXILIARES
# ===============================
function safe_delete_ns {
  local ns=$1
  if kubectl get ns "$ns" &> /dev/null; then
    echo "Deletando namespace $ns..."
    kubectl delete ns "$ns" --ignore-not-found
  else
    echo "Namespace $ns não existe, ignorando."
  fi
}

# ===============================
# PARAR O CLUSTER
# ===============================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Parando cluster K3d $CLUSTER_NAME..."
  k3d cluster stop "$CLUSTER_NAME"
else
  echo "Cluster $CLUSTER_NAME não existe."
fi

# ===============================
# DELETAR O CLUSTER
# ===============================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Deletando cluster K3d $CLUSTER_NAME..."
  k3d cluster delete "$CLUSTER_NAME"
else
  echo "Cluster $CLUSTER_NAME já foi deletado ou não existe."
fi

# ===============================
# REMOVER NAMESPACES (opcional)
# ===============================
for ns in "$ARGOCD_NAMESPACE" "$DEV_NAMESPACE"; do
  safe_delete_ns "$ns"
done

# ===============================
# LIMPAR CONTEXTOS DO KUBECTL
# ===============================
echo "Limpando contextos antigos do kubectl..."
kubectl config delete-context "$CLUSTER_NAME" &> /dev/null || true
kubectl config unset users."$CLUSTER_NAME-admin" &> /dev/null || true
kubectl config unset clusters."$CLUSTER_NAME" &> /dev/null || true

echo "=== Teardown concluído! Tudo removido com segurança ==="
