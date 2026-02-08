# Comandos – Inception of Things (Part 1)

- Entre no diretório raiz do arquivo "Vagrantfile" para executar o Vagrant.

---

## Subir e gerenciar as VMs (Vagrant)
Comando que sobe as máquinas virtuais:
- `vagrant up`

Comando que mostra o estado das VMs:
- `vagrant status`

Comando que acessa a VM via SSH:
- `vagrant ssh loginS`
- `vagrant ssh loginSW`

Comando que recria todo o ambiente:
- `vagrant destroy -f`

---

> Daqui em diante, os comandos deverão ser executados dentro da VM (após login ssh)


## Verificação de rede e IP
Comando que lista todas as interfaces de rede:
- `ip a`

Comando que mostra IPs de forma resumida:
- `ip -br addr`

Comando que mostra os dados de uma interface específica:
- `ip addr show eth1`
- `ip addr show enp0s8`

Comando que filtra apenas interfaces ativas:
- `ip link show up`

Comando que filtra pelo IP exigido no projeto:
- `ip a | grep 192.168.56`

---

## Hostname
Comando que mostra o hostname:
- `hostname`

Comando que mostra o hostname completo:
- `hostname -f`

Comando que verifica resolução local de nomes:
- `cat /etc/hosts`

---

## Verificação de recursos
Comando que mostra uso de memória:
- `free -m`

---

## Serviços no Alpine (OpenRC)
Comando que verifica o status do K3s no server:
- `rc-service k3s status`

Comando que verifica o status do agent no worker:
- `rc-service k3s-agent status`

Comando que reinicia o K3s:
- `rc-service k3s restart`

Comando que para e inicia o K3s:
- `rc-service k3s stop`
- `rc-service k3s start`

---

## Processos e portas
Comando que verifica se o K3s está rodando:
- `ps aux | grep k3s`

Comando que verifica o agent:
- `ps aux | grep k3s-agent`

Comando que verifica se a API está escutando:
- `ss -lntp | grep 6443`

---

## Logs
Comando que mostra os últimos logs do K3s:
- `tail -n 50 /var/log/k3s.log`

Comando que acompanha logs em tempo real:
- `tail -f /var/log/k3s.log`

Comando que navega nos logs:
- `less /var/log/k3s.log`

---

## Testes diretos da API Kubernetes
Comando que testa se o API Server está saudável:
- `curl -k https://127.0.0.1:6443/healthz`

---

## kubectl / Kubernetes
Comando que verifica a versão do kubectl:
- `kubectl version --client`

Comando que verifica se o control plane está acessível:
- `kubectl cluster-info`

Comando que lista os nodes:
- `kubectl get nodes`

Comando que lista nodes com saída mínima:
- `kubectl get nodes -o name`
- `kubectl get nodes --no-headers`

Comando mais leve para testar a API:
- `kubectl get --raw /healthz`

Comando que força o uso do kubeconfig do K3s:
- `kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes`

Comando usando kubectl embutido do K3s:
- `k3s kubectl get nodes`

---

## Kubeconfig
Comando que verifica onde está o kubectl:
- `which kubectl`

Comando que verifica o arquivo de configuração do cluster:
- `ls -l /etc/rancher/k3s/k3s.yaml`

Comando que exporta o kubeconfig:
- `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`

Comando que copia o kubeconfig para o usuário:
- `mkdir -p ~/.kube`
- `sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config`
- `sudo chown $USER:$USER ~/.kube/config`

---

## Worker
Comando que verifica o token do node worker:
- `cat /var/lib/rancher/k3s/server/node-token`

---

## Alias
Comando que cria um alias para kubectl:
- `alias k='kubectl'`

---

## Estrutura do projeto
Comando que verifica a estrutura da Part 1:
- `find p1 -maxdepth 2`

--

kubectl get ns
kubectl get pods -n argocd
kubectl port-forward svc/argocd-server -n argocd 8083:443

localhost:8083

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

k3d cluster stop <tab>
k3d cluster delete <tab>

# bonus

kubectl delete all --all


kubectl config current-context
kubectl get nodes
kubectl get pods -A
kubectl cluster-info


helm list -n gitlab
helm status gitlab -n gitlab
helm get values gitlab -n gitlab
kubectl get deployment -n gitlab -o wide

kubectl get pods -n gitlab
kubectl describe pod <gitlab-webservice-pod> -n gitlab | grep Image

commands:
kubectl config current-context
kubectl get nodes
k3d cluster list
docker ps --format "table {{.Names}}\t{{.Status}}"
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingressclass
kubectl get ns

# Delete the entire k3d cluster (kills everything inside Kubernetes)
k3d cluster delete bonus

# Delete the local registry
k3d registry delete local-registry

# Optional: prune leftover Docker junk
docker system prune -f

kubectl delete namespace gitlab argocd dev ingress-nginx


# stuff goes into ~/.kube
