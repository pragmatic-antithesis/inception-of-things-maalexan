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

    # -----------------------------------
    # ALLOWED CHANGES START - Using gitlab-ctl reconfigure
    # -----------------------------------
    echo "Running gitlab-ctl reconfigure to ensure root user is created..."

    # Run reconfigure to ensure all services are properly configured
    kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
      gitlab-ctl reconfigure >/dev/null 2>&1

    echo "Waiting for GitLab to fully initialize after reconfigure..."
    sleep 30

    # Wait for root user to be created
    echo "Verifying root user creation..."
    for i in {1..60}; do
      EXISTS=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
        gitlab-rails runner "puts User.exists?(username: 'root')" 2>/dev/null || echo "false")

      if [ "$EXISTS" = "true" ]; then
        echo "Root user exists."
        break
      fi

      echo "Root user not ready yet... (attempt $i/60)"
      sleep 10

      # If root still doesn't exist after 10 attempts, try reconfigure again
      if [ $i -eq 10 ]; then
        echo "Still waiting for root user, running reconfigure again..."
        kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
          gitlab-ctl reconfigure >/dev/null 2>&1
      fi
    done

    if [ "$EXISTS" != "true" ]; then
      echo "Root user did not become ready even after reconfigure attempts."
      exit 1
    fi

    echo "Setting root password..."
    kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
      gitlab-rails runner "
        u = User.find_by(username: 'root');
        if u
          u.password = '$GITLAB_PASSWORD';
          u.password_confirmation = '$GITLAB_PASSWORD';
          u.save!
          puts 'Password updated'
        else
          puts 'Root user not found'
          exit 1
        end
      " >/dev/null

    echo "Creating personal access token..."
    GITLAB_TOKEN=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
      gitlab-rails runner "
        u = User.find_by(username: 'root');
        if u
          token = u.personal_access_tokens.create(
            name: 'bootstrap-token',
            scopes: [:api],
            expires_at: 30.days.from_now
          );
          token.set_token(SecureRandom.hex(20));
          token.save!;
          puts token.token
        else
          puts ''
        end
      ")

    if [ -z "$GITLAB_TOKEN" ]; then
      echo "Failed to create token."
      exit 1
    fi
    echo "Token created: $GITLAB_TOKEN"

    # -----------------------------------
    # /END OF ALLOWED CHANGES
    # -----------------------------------

  echo "Checking if project 'iot' exists..."
  EXISTING=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
    gitlab-rails runner "
      puts Project.where(name: 'iot').exists?
    " | tr -d '\r')

  if [ "$EXISTING" = "true" ]; then
    echo "Project already exists. Skipping creation."
  else
    echo "Creating project 'iot'..."
    kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
      gitlab-rails runner "
        p = Project.create!(name: 'iot', visibility_level: 20)
        puts p.id
      "
    echo "Project created."
  fi

  save_stage "project_created"
fi




#################################
# ARGO CD
#################################

if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo "Installing Argo CD..."
  kubectl apply -n "$ARGOCD_NAMESPACE" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  wait_for_pods "$ARGOCD_NAMESPACE"

  kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" \
    -p '{"spec": {"type": "LoadBalancer"}}'

  HASH=$(htpasswd -bnBC 10 "" "$ARGOCD_ADMIN_PASSWORD" | awk -F: '{print $2}')

  kubectl -n "$ARGOCD_NAMESPACE" patch secret argocd-secret \
    -p "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"
fi

#################################
# DONE
#################################

echo "================================="
echo "Stage:          $BOOTSTRAP_STAGE"
echo "Cluster:        $CLUSTER_NAME"
echo "GitLab ns:      $GITLAB_NAMESPACE"
echo "Argo CD ns:     $ARGOCD_NAMESPACE"
echo "================================="
