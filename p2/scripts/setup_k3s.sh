#!/bin/ash

ip addr replace ${NODE_IP}/24 brd 192.168.56.255 dev eth1
ip link set eth1 up
ip route replace 192.168.56.0/24 dev eth1

curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="--node-ip=${NODE_IP} --flannel-iface=eth1" K3S_TOKEN=123 sh -

# Wait for Kubernetes API to be ready
until kubectl get nodes >/dev/null 2>&1; do
  sleep 2
done

kubectl apply -f ./confs
