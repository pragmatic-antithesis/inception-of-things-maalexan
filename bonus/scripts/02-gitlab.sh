helm repo add gitlab https://charts.gitlab.io/
helm repo update

helm install gitlab gitlab/gitlab \
  -n gitlab \
  --create-namespace \
  -f ../confs/gitlab-values.yaml \
  --timeout 20m
