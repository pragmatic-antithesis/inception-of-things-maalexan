#!/bin/bash
set -euo pipefail

# ===============================
# CONFIGS
# ===============================
if [ -f "../.env" ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo ".env not found! Creating a default one on parent folder"
  echo 'CLUSTER_NAME="p3-cluster"' >> ../.env
  echo 'ARGOCD_NAMESPACE="argocd"' >> ../.env
  echo 'DEV_NAMESPACE="dev"' >> ../.env
  echo 'ARGOCD_ADMIN_PASSWORD="admin123"' >> ../.env
  echo 'ARGOCD_PROJECT_YAML="./confs/argocd-project.yaml"' >> ../.env
  echo 'ARGOCD_APPLICATION_YAML="./confs/argocd-application.yaml"' >> ../.env
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

function wait_for_pods {
  local namespace=$1
  echo "Awaiting pods in $namespace enter Running state..."
  while [[ $(kubectl get pods -n "$namespace" --no-headers | grep -v Running | wc -l) -gt 0 ]]; do
    echo "Pods still starting..."
    sleep 3
  done
  echo "All pods $namespace are Running!"
}

# ===============================
# DEPENDENCIES
# ===============================
echo "=== Checking Dependencies ==="
check_install "docker" "sudo apt install -y docker.io && sudo systemctl enable docker --now"
check_install "kubectl" "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
check_install "k3d" "wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
check_install "htpasswd" "sudo apt install apache2-utils"

# ===============================
# K3D CLUSTER
# ===============================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME already exists"
else
  echo "Creating K3d cluster $CLUSTER_NAME..."
  k3d cluster create "$CLUSTER_NAME" \
    -p "8888:8888@loadbalancer" \
    -p "8080:80@loadbalancer" \
    --agents 2
fi

# ===============================
# NAMESPACES
# ===============================
for ns in "$ARGOCD_NAMESPACE" "$DEV_NAMESPACE"; do
  if kubectl get ns | grep -q "$ns"; then
    echo "Namespace $ns já existe"
  else
    echo "Criando namespace $ns..."
    kubectl create namespace "$ns"
  fi
done

# ===============================
# ARGO CD
# ===============================
if kubectl get deployment -n "$ARGOCD_NAMESPACE" argocd-server &> /dev/null; then
  echo "Argo CD already installed"
else
  echo "Installing Argo CD..."
  kubectl apply -n "$ARGOCD_NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  wait_for_pods "$ARGOCD_NAMESPACE"

  echo "Configuring Argo CD LoadBalancer..."
  kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" -p '{"spec": {"type": "LoadBalancer"}}'


  echo "Setting admin password..."
  HASH=$(htpasswd -bnBC 10 "" "$ARGOCD_ADMIN_PASSWORD" | awk -F: '{print $2}')
  kubectl -n "$ARGOCD_NAMESPACE" patch secret argocd-secret \
    -p "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"

  kubectl patch configmap argocd-cm -n "$ARGOCD_NAMESPACE" -p '{"data":{"timeout.reconciliation": "60s"}}'
fi

# ===============================
# HEALTHCHECK ARGO CD
# ===============================
echo "Checking Argo CD health..."
wait_for_pods "$ARGOCD_NAMESPACE"

# ===============================
# ARGO CD PROJECT
# ===============================
echo "Applying Argo CD project and application..."
kubectl apply -f "$ARGOCD_PROJECT_YAML" -n "$ARGOCD_NAMESPACE"
kubectl apply -f "$ARGOCD_APPLICATION_YAML" -n "$ARGOCD_NAMESPACE"

echo "=== Setup done! ==="
echo "Argo CD available in LoadBalancer (porta 8080 ou 8888)"
echo "Namespace dev ready to deploy your application"
