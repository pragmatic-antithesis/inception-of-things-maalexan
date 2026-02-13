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
  echo 'GITLAB_PASSWORD="gitlaber"' >> ../.env
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
    --timeout=10m
}

wait_for_gitlab_ready() {
  local ns="$1"
  local max_attempts=42
  local attempt=1

  echo "Waiting for GitLab to be fully ready (this can take 5-10 minutes)..."

  kubectl wait --for=condition=ready pod -n "$ns" -l app=gitlab --timeout=10m || true

  while [ $attempt -le $max_attempts ]; do
    if kubectl exec -n "$ns" deploy/gitlab -- curl -s -o /dev/null -w "%{http_code}" http://localhost:80/-/readiness 2>/dev/null | grep -q "200"; then
      echo "GitLab is ready!"
      return 0
    fi
    echo "Waiting for GitLab API... ($attempt/$max_attempts)"
    sleep 10
    attempt=$((attempt + 1))
  done

  echo "GitLab failed to become ready in time"
  return 1
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
        "htpasswd")
            check_install "htpasswd" "sudo apt install -y apache2-utils"
            ;;
        *)
            echo "Unknown tool: $1"
            echo "Available tools: docker, curl, kubectl, k3d, htpasswd"
            exit 1
            ;;
    esac
    exit 1
fi

for cmd in docker curl kubectl k3d htpasswd; do
  require_cmd "$cmd"
done

#################################
# REGISTRY
#################################
if ! k3d registry list | awk '{print $1}' | grep -qx "k3d-$REGISTRY_NAME"; then
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
# APPLY GITLAB MANIFESTS
#################################
echo "Applying GitLab manifests..."
kubectl apply -f ../confs/gitlab/namespace.yaml
kubectl apply -f ../confs/gitlab/deployment.yaml
kubectl apply -f ../confs/gitlab/service.yaml

# Wait for GitLab to be fully initialized
wait_for_gitlab_ready "$GITLAB_NAMESPACE"

#################################
# POPULATE GITLAB REPO
#################################
echo "Setting up GitLab repository..."

# Find a free port
FREE_PORT=8081
while lsof -i :$FREE_PORT &>/dev/null; do
  FREE_PORT=$((FREE_PORT + 1))
done
echo "Using port $FREE_PORT for GitLab"

kubectl port-forward -n "$GITLAB_NAMESPACE" svc/gitlab $FREE_PORT:80 &
PF_PID=$!
sleep 5

# Wait for GitLab API to be fully ready
echo "Waiting for GitLab API to be ready..."
max_retries=30
retry=0
while [ $retry -lt $max_retries ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" \
    "http://localhost:$FREE_PORT/api/v4/version")

  if [ "$HTTP_CODE" -eq 200 ]; then
    echo "GitLab API is ready!"
    break
  fi

  echo "GitLab API not ready yet (HTTP $HTTP_CODE), retrying... ($((retry+1))/$max_retries)"
  sleep 5
  retry=$((retry + 1))
done

if [ $retry -eq $max_retries ]; then
  echo "GitLab API never became ready. Exiting."
  kill $PF_PID 2>/dev/null || true
  exit 1
fi

# Create the project
echo "Creating root/iot project..."
CREATE_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" \
  -X POST "http://localhost:$FREE_PORT/api/v4/projects" \
  -d "name=iot&visibility=public")

if echo "$CREATE_RESPONSE" | grep -q '"id":'; then
  echo "Project created successfully"
  PROJECT_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  echo "Project ID: $PROJECT_ID"
else
  echo "Failed to create project. Response:"
  echo "$CREATE_RESPONSE"

  # Check if project already exists
  EXISTING=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" \
    "http://localhost:$FREE_PORT/api/v4/projects?search=iot")

  if echo "$EXISTING" | grep -q '"name":"iot"'; then
    echo "Project already exists, continuing..."
  else
    echo "Project creation failed. GitLab may still be initializing."
    echo "You can manually create the project later at http://localhost:$FREE_PORT"
    kill $PF_PID 2>/dev/null || true
    exit 1
  fi
fi

# Clone and push content
echo "Cloning from GitHub..."
if [ -d "/tmp/github-repo" ]; then
  rm -rf /tmp/github-repo
fi
git clone https://github.com/pragmatic-antithesis/inception-of-things-maalexan.git /tmp/github-repo

echo "Pushing to GitLab..."
# Try multiple times to clone
clone_success=false
for i in {1..5}; do
  if git clone http://root:$GITLAB_PASSWORD@localhost:$FREE_PORT/root/iot.git /tmp/gitlab-repo 2>/dev/null; then
    clone_success=true
    break
  fi
  echo "Clone attempt $i failed, retrying in 5 seconds..."
  sleep 5
done

if [ "$clone_success" = false ]; then
  echo "Failed to clone GitLab repo. GitLab might not be fully ready."
  kill $PF_PID 2>/dev/null || true
  exit 1
fi

mkdir -p /tmp/gitlab-repo/k8s
cp -r /tmp/github-repo/p3/confs/app/* /tmp/gitlab-repo/ 2>/dev/null || true
cp -r ../confs/k8s/* /tmp/gitlab-repo/k8s/ 2>/dev/null || true

cd /tmp/gitlab-repo
git add .
git config --global user.email "root@gitlab.local"
git config --global user.name "GitLab Root"
git commit -m "Initial commit" || echo "Nothing to commit"
git push origin main || echo "Push failed, but continuing..."

cd -
kill $PF_PID 2>/dev/null || true
rm -rf /tmp/github-repo /tmp/gitlab-repo

echo "GitLab repository population complete"

#################################
# ARGO CD
#################################
if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo "Installing Argo CD"
  kubectl apply --server-side -n "$ARGOCD_NAMESPACE" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  echo "Waiting for Argo CD pods..."
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
# CONFIGURE ARGO CD TO TRUST GITLAB
#################################
echo "Adding GitLab repository to Argo CD..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitlab-iot
  namespace: $ARGOCD_NAMESPACE
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: http://gitlab.gitlab.svc.cluster.local/root/iot.git
  insecure: "true"
  forceHttpBasicAuth: "true"
EOF

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
echo "GitLab repo:    http://localhost:8080/root/iot"
echo "GitLab root pw: $GITLAB_PASSWORD"
echo "Argo CD ns:     $ARGOCD_NAMESPACE"
echo "Argo CD admin:  admin / $ARGOCD_ADMIN_PASSWORD"
echo "Argo CD UI:     kubectl port-forward -n argocd svc/argocd-server 8081:443"
echo "Dev ns:         $DEV_NAMESPACE"
echo ""
echo "IMPORTANT: GitLab takes 5-10 minutes to fully initialize."
echo "If the repo creation failed, wait a few minutes and run:"
echo "  ./scripts/populate-gitlab.sh"
echo "================================="
