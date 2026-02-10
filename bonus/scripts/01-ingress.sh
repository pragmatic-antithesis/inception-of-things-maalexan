#!/usr/bin/env bash
set -e

echo "=== Creating ingress-nginx namespace ==="
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

echo "=== Installing ingress-nginx ==="

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml

echo "=== Waiting for ingress controller... ==="

kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo "=== Ingress installed ==="

kubectl get pods -n ingress-nginx

for ns in gitlab argocd dev; do
  echo "=== Creating namespace: $ns ==="
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

kubectl get ns
