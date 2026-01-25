#!/bin/ash

ip addr replace 192.168.56.110/24 dev eth1
ip link set eth1 up
ip route replace 192.168.56.0/24 dev eth1

curl -sfL https://get.k3s.io | sh -

# espera o cluster subir
sleep 10

kubectl apply -f /vagrant/confs
