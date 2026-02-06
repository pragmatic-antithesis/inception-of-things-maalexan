#!/usr/bin/env bash
set -e

echo "[+] Adding GitLab Helm repo"
helm repo add gitlab https://charts.gitlab.io/
helm repo update

echo "[+] Installing GitLab (this takes several minutes)"

helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=127.0.0.1 \
  --set global.edition=ce \
  --set global.ingress.configureCertmanager=false \
  --set certmanager.install=false \
  --set nginx-ingress.enabled=false \
  --set global.ingress.class=nginx \
  --set prometheus.install=false \
  --set gitlab-runner.install=false \
  --set registry.enabled=false \
  --set global.minio.enabled=false \
  --set postgresql.image.tag=14 \
  --set gitlab.webservice.replicaCount=1 \
  --timeout 15m

echo "[+] Waiting for GitLab webservice..."

kubectl wait \
  --namespace gitlab \
  --for=condition=Available deployment/gitlab-webservice-default \
  --timeout=900s

echo "[+] GitLab installed"
