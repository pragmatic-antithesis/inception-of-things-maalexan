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
function check_install {
  local cmd=$1
  local install_cmd=$2

  if ! command -v "$cmd" &> /dev/null; then
    echo "Instalando $cmd..."
    eval "$install_cmd"
  else
    echo "$cmd já instalado"
  fi
}

function wait_for_pods {
  local namespace=$1
  echo "Aguardando pods em $namespace estarem em estado Running..."
  while [[ $(kubectl get pods -n "$namespace" --no-headers | grep -v Running | wc -l) -gt 0 ]]; do
    echo "Pods ainda inicializando..."
    sleep 3
  done
  echo "Todos os pods em $namespace estão Running!"
}

# ===============================
# INSTALAÇÕES
# ===============================
echo "=== Verificando dependências ==="
check_install "htpasswd" "sudo apt update && sudo apt install -y apache2-utils"
check_install "docker" "sudo apt install -y docker.io && sudo systemctl enable docker --now"
check_install "k3d" "wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
check_install "kubectl" "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
rm -rf ./kubectl

# ===============================
# CRIAR CLUSTER K3D
# ===============================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME já existe"
else
  echo "Criando cluster K3d $CLUSTER_NAME..."
  k3d cluster create "$CLUSTER_NAME" \
    -p "8081:8081@loadbalancer" \
    -p "8080:80@loadbalancer" \
    --agents 2
fi

# ===============================
# CRIAR NAMESPACES
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
# INSTALAR ARGO CD
# ===============================
if kubectl get deployment -n "$ARGOCD_NAMESPACE" argocd-server &> /dev/null; then
  echo "Argo CD já instalado"
else
  echo "Instalando Argo CD..."
  kubectl apply -n "$ARGOCD_NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  # Esperar pods subirem
  wait_for_pods "$ARGOCD_NAMESPACE"

  # Configurar Argo CD LoadBalancer
  echo "Configurando Argo CD LoadBalancer..."
  kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" -p '{"spec": {"type": "LoadBalancer"}}'

  # Definir senha admin customizada
  echo "Definindo senha do admin..."
  HASH=$(htpasswd -bnBC 10 admin "$ARGOCD_ADMIN_PASSWORD" | awk -F: '{print $2}')
  kubectl -n "$ARGOCD_NAMESPACE" patch secret argocd-secret \
    -p "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"

  # Ajustar timeout de reconciliação
  kubectl patch configmap argocd-cm -n "$ARGOCD_NAMESPACE" -p '{"data":{"timeout.reconciliation": "60s"}}'
fi

# ===============================
# HEALTHCHECK ARGO CD
# ===============================
echo "Checando saúde dos pods do Argo CD..."
wait_for_pods "$ARGOCD_NAMESPACE"

# ===============================
# CRIAR PROJETO E APLICAÇÃO NO ARGO CD
# ===============================
echo "Aplicando Argo CD project e application..."
kubectl apply -f "$ARGOCD_PROJECT_YAML" -n "$ARGOCD_NAMESPACE"
kubectl apply -f "$ARGOCD_APPLICATION_YAML" -n "$ARGOCD_NAMESPACE"

echo "=== Setup concluído! ==="
echo "Argo CD disponível em LoadBalancer (porta 8080 ou 8081)"
echo "Namespace dev pronto para deploy da sua aplicação"
