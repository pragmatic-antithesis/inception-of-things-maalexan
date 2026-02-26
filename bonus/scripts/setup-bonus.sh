#!/usr/bin/env bash
set -euo pipefail

#################################
# CONFIG
#################################

ENV_FILE="../.env"

if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
else
  echo ".env not found! Creating a default one on parent folder"

  cat <<EOF > "$ENV_FILE"
CLUSTER_NAME="bonus"
REGISTRY_NAME="local-registry"
REGISTRY_PORT="4242"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
GITLAB_NAMESPACE="gitlab"
GITLAB_PASSWORD="gitlaber"
ARGOCD_ADMIN_PASSWORD="admin123"
ARGOCD_PROJECT_YAML="../confs/argocd/project.yaml"
ARGOCD_APPLICATION_YAML="../confs/argocd/application.yaml"
BOOTSTRAP_STAGE="init"
EOF

  echo ".env created. Re-run script."
  exit 1
fi

BOOTSTRAP_STAGE="${BOOTSTRAP_STAGE:-init}"

save_stage() {
  sed -i "s/^BOOTSTRAP_STAGE=.*/BOOTSTRAP_STAGE=\"$1\"/" "$ENV_FILE"
  export BOOTSTRAP_STAGE="$1"
  echo "==> Stage updated to: $BOOTSTRAP_STAGE"
}

#################################
# HELPERS
#################################

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1"
    exec "../../p3/scripts/setup.sh" "bonus"
    exit 1
  }
}

ensure_namespace() {
  local ns="$1"
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
}

wait_for_gitlab_ready() {
  local ns="$1"

  echo "Waiting for GitLab pod readiness..."
  kubectl wait --for=condition=Ready pod -n "$ns" -l app=gitlab --timeout=30m || true

  echo "Waiting for HTTP readiness endpoint..."
  until kubectl exec -n "$ns" deploy/gitlab -- \
    curl -sf http://localhost/-/readiness >/dev/null 2>&1; do
    echo "HTTP not ready..."
    sleep 15
  done

  echo "GitLab fully ready."
}

wait_for_pods() {
  local ns="$1"
  kubectl wait pod --namespace "$ns" --all --for=condition=Ready --timeout=15m
}

#################################
# DEPENDENCIES
#################################

for cmd in docker curl kubectl k3d htpasswd git; do
  require_cmd "$cmd"
done

#################################
# REGISTRY
#################################

if ! k3d registry list | awk '{print $1}' | grep -qx "k3d-$REGISTRY_NAME"; then
  echo "Creating registry $REGISTRY_NAME"
  k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT"
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
fi

kubectl config use-context "k3d-$CLUSTER_NAME"

#################################
# NAMESPACES
#################################

ensure_namespace "$GITLAB_NAMESPACE"
ensure_namespace "$ARGOCD_NAMESPACE"
ensure_namespace "$DEV_NAMESPACE"

#################################
# GITLAB IMAGE (idempotent)
#################################

if [ "$BOOTSTRAP_STAGE" = "init" ]; then
  echo "Pre-pulling GitLab latest image..."
  docker pull gitlab/gitlab-ce:latest

  echo "Importing image into k3d cluster..."
  k3d image import gitlab/gitlab-ce:latest -c "$CLUSTER_NAME"

  save_stage "image_ready"
fi

#################################
# APPLY GITLAB
#################################

if [ "$BOOTSTRAP_STAGE" = "image_ready" ]; then
  echo "Applying GitLab manifests..."
  kubectl apply -f ../confs/gitlab/pvc.yaml
  kubectl apply -f ../confs/gitlab/namespace.yaml
  kubectl apply -f ../confs/gitlab/deployment.yaml
  kubectl apply -f ../confs/gitlab/service.yaml

  save_stage "gitlab_deployed"
fi

#################################
# WAIT GITLAB
#################################

if [ "$BOOTSTRAP_STAGE" = "gitlab_deployed" ]; then
  wait_for_gitlab_ready "$GITLAB_NAMESPACE"
  echo "Try to create admin (rails takes forever)"
  kubectl exec -n gitlab deploy/gitlab -- gitlab-rails runner "
    User.create!(
      username: 'admin',
      email: 'admin@local.host',
      password: $GITLAB_PASSWORD,
      password_confirmation: $GITLAB_PASSWORD,
      admin: true,
      confirmed_at: Time.now,
      state: 'active'
    )
    puts 'Admin created'
  "
  save_stage "gitlab_ready"
fi

#################################
# CREATE PROJECT
#################################

if [ "$BOOTSTRAP_STAGE" = "gitlab_ready" ]; then
  echo "Setting up GitLab repository..."

  # -----------------------------------
  # Get GitLab pod
  # -----------------------------------
  POD_NAME=$(kubectl get pod -n "$GITLAB_NAMESPACE" -l app=gitlab \
    -o jsonpath='{.items[0].metadata.name}')

  if [ -z "$POD_NAME" ]; then
    echo "GitLab pod not found."
    exit 1
  fi

  echo "Waiting for database to be ready..."
  for i in {1..30}; do
  if kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
    gitlab-psql -d gitlabhq_production -c "SELECT 1" >/dev/null 2>&1; then
    echo "Database is responsive."
    break
  fi
  sleep 5
  done

  echo "Checking if project 'iot' exists..."
  PROJECT_EXISTS=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
  gitlab-psql -d gitlabhq_production -t -c "SELECT COUNT(*) FROM projects WHERE name = 'iot';" | tr -d ' ')

  if [ "$PROJECT_EXISTS" = "0" ]; then
    echo "Please create project 'iot' as gitlab user"
    exit 1
  fi

  save_stage "project_created"
fi

# ===============================
# ARGO CD
# ===============================
if [ "$BOOTSTRAP_STAGE" = "project_created" ]; then
    if kubectl get deployment -n "$ARGOCD_NAMESPACE" argocd-server &> /dev/null; then
    echo "Argo CD already installed"
    else
    echo "Installing Argo CD..."
    kubectl apply --server-side -n "$ARGOCD_NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

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

    save_stage "config_done"
fi
#################################
# DONE
#################################
if [ "$BOOTSTRAP_STAGE" = "config_done" ]; then
    echo "================================="
    echo "Stage:          $BOOTSTRAP_STAGE"
    echo "Cluster:        $CLUSTER_NAME"
    echo "GitLab ns:      $GITLAB_NAMESPACE"
    echo "Argo CD ns:     $ARGOCD_NAMESPACE"
    echo "================================="
else
    echo "Your configuration file is missing or in an unknown state, fix $ENV_FILE or delete it and run this again"
fi
