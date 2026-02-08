helm repo add gitlab https://charts.gitlab.io/
helm repo update

helm install gitlab gitlab/gitlab \
  -n gitlab \
  --create-namespace \
  -f gitlab-values.yaml \
  --timeout 20m
