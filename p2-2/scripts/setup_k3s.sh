#!/bin/ash
set -e

# Detecta automaticamente a interface da rede privada
IFACE=$(ip route | awk '/192.168.56.0\/24/ {print $3}')

if [ -z "$IFACE" ]; then
  echo "ERROR: não foi possível detectar a interface da rede privada"
  exit 1
fi

# Configura IP e rota
ip addr replace ${NODE_IP}/24 brd 192.168.56.255 dev ${IFACE}
ip link set ${IFACE} up
ip route replace 192.168.56.0/24 dev ${IFACE}

# Instala k3s
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--node-ip=${NODE_IP} --flannel-iface=${IFACE}" sh -

# Aguarda API do Kubernetes ficar disponível
until /usr/local/bin/kubectl get nodes >/dev/null 2>&1; do
  sleep 2
done

# Aplica manifests
if [ ! -d ./confs ]; then
  echo "ERROR: ./confs not found"
  exit 1
fi

/usr/local/bin/kubectl apply -f ./confs
