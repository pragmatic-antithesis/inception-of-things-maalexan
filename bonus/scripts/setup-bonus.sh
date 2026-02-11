#!/usr/bin/env bash
set -euo pipefail

#################################
# CONFIG
#################################
if [ -f "../.env" ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo ".env not found! Creating a default one on parent folder"
  echo 'CLUSTER_NAME="bonus"' >> ../.env
  echo 'REGISTRY_NAME="local-registry"' >> ../.env
  echo 'REGISTRY_PORT="4242"' >> ../.env
  echo 'ARGOCD_NAMESPACE="argocd"' >> ../.env
  echo 'DEV_NAMESPACE="dev"' >> ../.env
  echo 'GITLAB_NAMESPACE="gitlab"' >> ../.env
  echo 'ARGOCD_ADMIN_PASSWORD="admin123"' >> ../.env
  echo 'ARGOCD_PROJECT_YAML="../confs/argocd/project.yaml"' >> ../.env
  echo 'ARGOCD_APPLICATION_YAML="../confs/argocd/application.yaml"' >> ../.env
  exit 1
fi


#################################
# HELPERS
#################################
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1"
    echo "You can try to install it with $0 $1"
    exit 1
  }
}

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

ensure_namespace() {
  local ns="$1"
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
}

wait_for_pods() {
  local ns="$1"
  kubectl wait pod \
    --namespace "$ns" \
    --all \
    --for=condition=Ready \
    --timeout=15m
}

#################################
# DEPENDENCIES
#################################
if [ "$#" -eq 1 ]; then
    case $1 in
        "docker")
            check_install "docker" "sudo apt install -y docker.io && sudo systemctl enable docker --now && sudo usermod -aG docker $USER && su - $USER"
            ;;
        "curl")
            check_install "curl" "sudo apt install -y curl"
            ;;
        "kubectl")
            check_install "kubectl" "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl"
            ;;
        "k3d")
            check_install "k3d" "wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
            ;;
        "helm")
            check_install "helm" "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
            ;;
        "htpasswd")
            check_install "htpasswd" "sudo apt install -y apache2-utils"
            ;;
        *)
            echo "Unknown tool: $1"
            echo "Available tools: docker, curl, kubectl, k3d, htpasswd, helm"
            exit 1
            ;;
    esac
    exit 1
fi

for cmd in docker kubectl k3d helm curl htpasswd; do
  require_cmd "$cmd"
done

#################################
# REGISTRY
#################################
if ! k3d registry list | awk '{print $1}' | grep -qx "$REGISTRY_NAME"; then
  echo "Creating registry $REGISTRY_NAME"
  k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT"
else
  echo "Registry $REGISTRY_NAME already exists"
fi

#################################
# CLUSTER
#################################
if ! k3d cluster list | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "Creating cluster $CLUSTER_NAME"
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 \
    --agents 2 \
    --registry-use "k3d-$REGISTRY_NAME:$REGISTRY_PORT" \
    -p "8080:80@loadbalancer" \
    -p "8443:443@loadbalancer"
else
  echo "Cluster $CLUSTER_NAME already exists"
fi

kubectl config use-context "k3d-$CLUSTER_NAME"

#################################
# CORE NAMESPACES
#################################
ensure_namespace "$GITLAB_NAMESPACE"
ensure_namespace "$ARGOCD_NAMESPACE"
ensure_namespace "$DEV_NAMESPACE"

#################################
# GITLAB (Helm, idempotent)
#################################
helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
helm repo update

helm upgrade --install gitlab gitlab/gitlab \
  -n "$GITLAB_NAMESPACE" \
  -f ../confs/gitlab/gitlab-values.yaml \
  --timeout 30m

#################################
# ARGO CD
#################################
if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo "Installing Argo CD"
  kubectl apply --server-side -n "$ARGOCD_NAMESPACE" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    wait_for_pods "$ARGOCD_NAMESPACE"

    echo "Configuring Argo CD LoadBalancer..."
    kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" -p '{"spec": {"type": "LoadBalancer"}}'

    echo "Setting admin password..."
    HASH=$(htpasswd -bnBC 10 "" "$ARGOCD_ADMIN_PASSWORD" | awk -F: '{print $2}')
    kubectl -n "$ARGOCD_NAMESPACE" patch secret argocd-secret \
      -p "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"

    kubectl patch configmap argocd-cm -n "$ARGOCD_NAMESPACE" -p '{"data":{"timeout.reconciliation": "60s"}}'
else
  echo "Argo CD already installed"
fi

#################################
# HEALTHCHECK ARGO CD
#################################
echo "Checking Argo CD health..."
wait_for_pods "$ARGOCD_NAMESPACE"

#################################
# ARGO CD CONFIG (project + app)
#################################
kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_PROJECT_YAML"
kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_APPLICATION_YAML"

#################################
# DONE
#################################
echo "================================="
echo "Cluster:        $CLUSTER_NAME"
echo "GitLab ns:      $GITLAB_NAMESPACE"
echo "Argo CD ns:     $ARGOCD_NAMESPACE"
echo "Dev ns:         $DEV_NAMESPACE"
echo "Safe to rerun."
echo "================================="
