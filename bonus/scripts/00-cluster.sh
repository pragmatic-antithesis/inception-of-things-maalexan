#!/usr/bin/env bash

set -e

# ===============================
# CONFIGS
# ===============================
if [ -f "../.env" ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo ".env not found! Creating a default one on parent folder"
  echo 'CLUSTER_NAME=bonus' >> ../.env
  echo 'REGISTRY_NAME=local-registry' >> ../.env
  echo 'REGISTRY_PORT=4242' >> ../.env
  exit 1
fi

# ===============================
# HELPERS
# ===============================
function check_install {
  local cmd=$1
  local install_cmd=$2

  if ! command -v "$cmd" &> /dev/null; then
    echo "Installing $cmd..."
    eval "$install_cmd"
  else
    echo "$cmd already installed"
  fi
}

# ===============================
# DEPENDENCIES
# ===============================
echo "=== Checking Dependencies ==="
check_install "docker" "sudo apt install -y docker.io && sudo systemctl enable docker --now && sudo usermod -aG docker $USER && su - $USER"
check_install "curl" "sudo apt install curl"
check_install "kubectl" "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl"
check_install "k3d" "wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
check_install "helm" "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

echo "=== Creating local registry ==="

if ! docker ps | grep -q ${REGISTRY_NAME}; then
  k3d registry create ${REGISTRY_NAME} --port ${REGISTRY_PORT}
else
  echo "=== Registry already exists ==="
fi

echo "=== Creating k3d cluster ==="

if ! k3d cluster list | grep -q ${CLUSTER_NAME}; then

k3d cluster create ${CLUSTER_NAME} \
  --servers 1 \
  --agents 2 \
  --registry-use k3d-${REGISTRY_NAME}:${REGISTRY_PORT} \
  -p "8080:80@loadbalancer" \
  -p "8443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

else
  echo "=== Cluster already exists ==="
fi

echo "=== Setting kubectl context ==="
kubectl config use-context k3d-${CLUSTER_NAME}

echo "Cluster nodes:"
kubectl get nodes
