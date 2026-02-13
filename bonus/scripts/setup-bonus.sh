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
    --timeout=5m
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
kubectl apply -f ../confs/gitlab/configmap.yaml
kubectl apply -f ../confs/gitlab/deployment.yaml
kubectl apply -f ../confs/gitlab/service.yaml

echo "Waiting for GitLab to start (this shouldn't take more than 3 minutes)..."
wait_for_deployment "$GITLAB_NAMESPACE" "gitlab"
sleep 180

#################################
# POPULATE GITLAB REPO
#################################
echo "Setting up GitLab repository..."

kubectl port-forward -n "$GITLAB_NAMESPACE" svc/gitlab 8080:80 &
PF_PID=$!
sleep 10

curl --fail --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" \
  -X POST "http://localhost:8080/api/v4/projects" \
  -d "name=iot&visibility=public" || {
    echo "Retrying repository creation..."
    sleep 30
    curl --fail --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" \
      -X POST "http://localhost:8080/api/v4/projects" \
      -d "name=iot&visibility=public"
  }

git clone https://github.com/pragmatic-antithesis/inception-of-things-maalexan.git /tmp/github-repo
git clone http://root:$GITLAB_PASSWORD@localhost:8080/root/iot.git /tmp/gitlab-repo

cp -r /tmp/github-repo/p3/confs/app/* /tmp/gitlab-repo/
cp -r ../confs/k8s/* /tmp/gitlab-repo/k8s/

cd /tmp/gitlab-repo
git add .
git config --global user.email "root@gitlab.local"
git config --global user.name "GitLab Root"
git commit -m "Initial commit"
git push origin main
cd -

kill $PF_PID
rm -rf /tmp/github-repo /tmp/gitlab-repo

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
echo "================================="
