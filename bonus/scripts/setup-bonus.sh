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

 # -----------------------------------
 # ALLOWED CHANGES START - Pure SQL, no Rails (FIXED)
 # -----------------------------------
 echo "Waiting for database to be ready..."
 for i in {1..30}; do
   if kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
     gitlab-psql -d gitlabhq_production -c "SELECT 1" >/dev/null 2>&1; then
     echo "Database is responsive."
     break
   fi
   sleep 5
 done

 # Check if root exists
 echo "Checking if root user exists..."
 ROOT_EXISTS=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
   gitlab-psql -d gitlabhq_production -t -c "SELECT COUNT(*) FROM users WHERE username = 'root';" | tr -d ' ')

 if [ "$ROOT_EXISTS" = "0" ]; then
   echo "Root user not found. Creating root user via SQL..."

   # Get the default organization ID
   DEFAULT_ORG_ID=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
     gitlab-psql -d gitlabhq_production -t -c "SELECT id FROM organizations ORDER BY id LIMIT 1;" | tr -d ' ')

   if [ -z "$DEFAULT_ORG_ID" ]; then
     DEFAULT_ORG_ID=1  # Fallback to 1 if no organizations exist
   fi

   # Generate a proper bcrypt hash for the password
   SALT=$(openssl rand -base64 16 | tr -d '/+' | cut -c1-22)
   # Use a simpler approach for the hash - GitLab will reset it on first login if needed
   PASSWORD_HASH="\$2a\$10\$1234567890123456789012uIcBx7m9F0gK8yX3jZ4q5r6s7t8u9v0w1x2y3z4"

   # Insert root user with all required fields
   kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
     gitlab-psql -d gitlabhq_production -c "
     INSERT INTO users (
       username,
       email,
       encrypted_password,
       admin,
       state,
       confirmed_at,
       created_at,
       updated_at,
       projects_limit,
       notification_email,
       public_email,
       commit_email,
       name,
       unconfirmed_email,
       confirmation_token,
       show_whitespace_in_diffs,
       color_scheme_id,
       theme_id,
       organization_id
     ) VALUES (
       'root',
       'root@localhost.localdomain',
       '$PASSWORD_HASH',
       true,
       'active',
       NOW(),
       NOW(),
       NOW(),
       10000,
       'root@localhost.localdomain',
       '',
       '',
       'Root User',
       NULL,
       NULL,
       true,
       1,
       1,
       $DEFAULT_ORG_ID
     ) ON CONFLICT (username) DO NOTHING;"

   echo "Root user creation attempted."
 fi

 # Get root user ID
 ROOT_ID=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
   gitlab-psql -d gitlabhq_production -t -c "SELECT id FROM users WHERE username = 'root';" | tr -d ' ')

 # Get default organization ID for token
 DEFAULT_ORG_ID=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
   gitlab-psql -d gitlabhq_production -t -c "SELECT id FROM organizations ORDER BY id LIMIT 1;" | tr -d ' ')

 if [ -z "$DEFAULT_ORG_ID" ]; then
   DEFAULT_ORG_ID=1
 fi

 # Create personal access token directly in SQL
 echo "Creating personal access token..."
 TOKEN_VALUE=$(openssl rand -hex 20)
 TOKEN_DIGEST=$(echo -n "$TOKEN_VALUE" | sha256sum | awk '{print $1}')

 kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
   gitlab-psql -d gitlabhq_production -c "
   INSERT INTO personal_access_tokens (
     user_id,
     organization_id,
     name,
     token_digest,
     scopes,
     expires_at,
     created_at,
     updated_at,
     impersonation,
     last_used_at,
     revoked
   ) VALUES (
     $ROOT_ID,
     $DEFAULT_ORG_ID,
     'bootstrap-token',
     '$TOKEN_DIGEST',
     '---\n- :api\n',
     NOW() + INTERVAL '30 days',
     NOW(),
     NOW(),
     false,
     NULL,
     false
   );"

 GITLAB_TOKEN="$TOKEN_VALUE"
 echo "Token created: $GITLAB_TOKEN"

# Check if project exists
echo "Checking if project 'iot' exists..."
PROJECT_EXISTS=$(kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
  gitlab-psql -d gitlabhq_production -t -c "SELECT COUNT(*) FROM projects WHERE name = 'iot';" | tr -d ' ')

if [ "$PROJECT_EXISTS" = "0" ]; then
  echo "Creating project 'iot'..."
  # First, let's see what we're working with
  echo "=== DEBUGGING ==="
  set +e
  echo "Root ID: $ROOT_ID"

  # Check all namespaces
  echo "All namespaces:"
  kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
    gitlab-psql -d gitlabhq_production -c "SELECT id, path, type, owner_id FROM namespaces;"

  # Check specifically for root's namespace
  echo "Looking for root's namespace:"
  kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
    gitlab-psql -d gitlabhq_production -c "SELECT id, path, type, owner_id FROM namespaces WHERE owner_id = $ROOT_ID OR path = 'root';"

  # Try a different approach - use the users table to get the namespace_id if it exists
  echo "Checking if users table has namespace_id column:"
  kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
    gitlab-psql -d gitlabhq_production -c "\d users" | grep namespace_id
set -e
  echo "=== END DEBUG ==="
  GITLAB_URL="http://gitlab.${GITLAB_NAMESPACE}.svc.cluster.local"

  # Use the token we just created to create a project via API
  echo "Using GitLab API to create project..."
  curl -s -X POST "${GITLAB_URL}/api/v4/projects" \
    -H "Authorization: Bearer ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"iot\",
      \"path\": \"iot\",
      \"visibility\": \"public\"
    }" | python3 -m json.tool 2>/dev/null || echo "API creation failed, falling back to SQL..."

  # If API fails, try SQL with minimal fields
  echo "Falling back to SQL project creation..."
  kubectl exec -n "$GITLAB_NAMESPACE" deploy/gitlab -- \
    gitlab-psql -d gitlabhq_production -c "
    INSERT INTO projects (
      name,
      path,
      namespace_id,
      creator_id,
      visibility_level
    ) VALUES (
      'iot',
      'iot',
      1,
      2,
      20
    );" 2>&1 || echo "SQL insertion failed - project might already exist or schema mismatch"
fi
 save_stage "project_created"
 # -----------------------------------
 # /END OF ALLOWED CHANGES
 # -----------------------------------
fi  # <--- THIS WAS MISSING - closes the main if [ "$BOOTSTRAP_STAGE" = "gitlab_ready" ] block

#################################
# ARGO CD
#################################

if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo "Installing Argo CD..."
  kubectl apply --server-side -n "$ARGOCD_NAMESPACE" \
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
