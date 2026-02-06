#!/usr/bin/env bash

if ! command -v helm >/dev/null 2>&1; then
  echo "[+] Installing Helm"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "[=] Helm already installed"
fi

set -e

CLUSTER_NAME=bonus
REGISTRY_NAME=local-registry
REGISTRY_PORT=4242

echo "[+] Creating local registry"

if ! docker ps | grep -q ${REGISTRY_NAME}; then
  k3d registry create ${REGISTRY_NAME} --port ${REGISTRY_PORT}
else
  echo "[=] Registry already exists"
fi

echo "[+] Creating k3d cluster"

if ! k3d cluster list | grep -q ${CLUSTER_NAME}; then

k3d cluster create ${CLUSTER_NAME} \
  --servers 1 \
  --agents 2 \
  --registry-use k3d-${REGISTRY_NAME}:${REGISTRY_PORT} \
  -p "8080:80@loadbalancer" \
  -p "8443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

else
  echo "[=] Cluster already exists"
fi

echo "[+] Setting kubectl context"
kubectl config use-context k3d-${CLUSTER_NAME}

echo "[+] Cluster nodes:"
kubectl get nodes
