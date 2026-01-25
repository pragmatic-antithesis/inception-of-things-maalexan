#!/bin/ash

sudo ip addr replace ${NODE_IP}/24 brd 192.168.56.255 dev eth1
ip link set eth1 up
if [ "$K3S_ROLE" = "server" ]; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=${NODE_IP} --flannel-iface=eth1" K3S_TOKEN=4242 sh -
    k3s="k3s"
elif [ "$K3S_ROLE" = "worker" ]; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://192.168.56.110:6443 --token 4242 --flannel-iface=eth1 --node-ip=${NODE_IP}" sh -s -
    k3s="k3s-agent"
fi
ip route replace 192.168.56.0/24 dev eth1

service $k3s restart
