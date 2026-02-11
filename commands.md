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

# Bonus Part Testing Guide
# =========================

# Prerequisites Verification
# ------------------------

 # Check everything is running
 k3d cluster list
 k3d registry list
 kubectl get nodes


# 1. Access GitLab
# ---------------

 # Port-forward GitLab
 # In a separate terminal, keep this running
 kubectl port-forward -n gitlab svc/gitlab-webservice-default 8080:8080

 # Get GitLab root password
 kubectl get secret gitlab-gitlab-initial-root-password
 -n gitlab
 -o jsonpath="{.data.password}"  base64 -d

 # Access GitLab Web UI
 1. Open browser: http://localhost:8080
 2. Username: root
 3. Password: [the password from above]

 # Verify: You should see GitLab's welcome page and the root/iot repository already populated.


# 2. Access Argo CD
# ----------------

 # Port-forward Argo CD
 # In a separate terminal, keep this running
 kubectl port-forward -n argocd svc/argocd-server 8081:443

 # Get Argo CD initial password
 # If you didn't set a custom password
 kubectl get secret argocd-initial-admin-secret
 -n argocd
 -o jsonpath="{.data.password}"  base64 -d

 # Or if you used the script with ARGOCD_ADMIN_PASSWORD="admin123"
 # Username: admin
 # Password: admin123

 # Access Argo CD Web UI
 1. Open browser: https://localhost:8081
 2. Accept the self-signed certificate warning
 3. Login with credentials above

 # Verify: You should see the bonus-playground application, but it might be in "Missing" or "OutOfSync" state initially.


# 3. Configure Local DNS (/etc/hosts)
# ----------------------------------

 # Edit /etc/hosts (requires sudo)
 sudo nano /etc/hosts

 # Add this line
 127.0.0.1 bonus.playground.localhost

 # Verify:
 ping -c 1 bonus.playground.localhost
 # Should reply from 127.0.0.1


# 4. Test the Deployed Application
# -------------------------------

 # Check if the app is running
 # Wait for Argo CD to sync (may take 1-2 minutes)
 kubectl get pods -n dev
 kubectl get svc -n dev
 kubectl get ingress -n dev

 # Port-forward the service directly (if Ingress isn't working)
 # In a separate terminal
 kubectl port-forward -n dev svc/wil-playground 8888:8888

 # Test the application
 # Test via port-forward
 curl http://localhost:8888

 # Expected output:
 # {"status":"ok", "message": "v1"}

 # Test via Ingress (requires /etc/hosts entry)
 curl http://bonus.playground.localhost

 # Browser access:
 # - Via port-forward: http://localhost:8888
 # - Via Ingress: http://bonus.playground.localhost


# 5. Test Version Switching (The Main Demo)
# ----------------------------------------

 # Step 1: Verify current version
 # Check the running image version
 kubectl get deployment -n dev -o yaml | grep image

 # Check the application response
 curl http://localhost:8888
 # Should say "v1"

 # Step 2: Clone your GitLab repository
 # Get GitLab password again if needed
 GITLAB_PW=$(kubectl get secret gitlab-gitlab-initial-root-password
 -n gitlab
 -o jsonpath="{.data.password}"  base64 -d)

 # Clone the repo
 git clone http://root:$GITLAB_PW@localhost:8080/root/iot.git
 cd iot

 # Step 3: Switch from v1 to v2
 # Find the deployment file (may be deployment.yaml or similar)
 # Change the image tag from v1 to v2
 sed -i 's/wil42/playground:v1/wil42/playground:v2/g' deployment.yaml

 # Verify the change
 grep "image:" deployment.yaml
 # Should show: image: wil42/playground:v2

 # Step 4: Commit and push
 git add deployment.yaml
 git commit -m "Switch application to v2"
 git push origin main

 # Step 5: Watch Argo CD sync
 # Watch the sync status
 kubectl get application -n argocd bonus-playground -w

 # Or via Argo CD UI: https://localhost:8081
 # You should see:
 # 1. OutOfSync (detected change)
 # 2. Syncing (deploying new version)
 # 3. Synced/Healthy (deployment complete)

 # Step 6: Verify v2 is running
 # Wait for new pod to be ready
 kubectl get pods -n dev -w

 # Test the application
 curl http://localhost:8888
 # Should now say "v2"

 # Check the pod image
 kubectl get deployment -n dev -o yaml | grep image
 # Should show v2

 # Step 7: Switch back to v1 (to prove it works both ways)
 cd iot
 sed -i 's/wil42/playground:v2/wil42/playground:v1/g' deployment.yaml
 git add deployment.yaml
 git commit -m "Switch back to v1"
 git push origin main

 # Wait for sync and verify
 curl http://localhost:8888
 # Should be back to "v1"


# 6. Troubleshooting Commands
# --------------------------

 # Check Argo CD can reach GitLab
 # Exec into Argo CD repo server
 kubectl exec -n argocd deploy/argocd-repo-server -it --
 curl -I http://gitlab.gitlab.svc.cluster.local
 # Should return HTTP 200

 # Force Argo CD to refresh
 argocd app sync bonus-playground
 # Or via kubectl
 kubectl patch application -n argocd bonus-playground
 --type merge
 -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

 # Check application logs
 # Get the pod name
 POD=$(kubectl get pods -n dev -l app=wil-playground -o jsonpath="{.items[0].metadata.name}")

 # View logs
 kubectl logs -n dev $POD

 # Delete stuck resources
 # Force delete Argo CD application if stuck
 kubectl delete application -n argocd bonus-playground --force --grace-period=0

 # Reapply
 kubectl apply -n argocd -f ../confs/argocd/application.yaml


# 7. Complete Cleanup
# ------------------

 # From the bonus/scripts directory
 ./clean.sh

 # Verify cleanup
 k3d cluster list # Should show no bonus cluster
 docker ps | grep k3d # Should show only registry container (stopped)


# Demo Script (For Defense)
# ------------------------

 1. Show infrastructure: kubectl get ns, kubectl get pods -A
 2. Show GitLab: port-forward, browser to localhost:8080, show root/iot repo
 3. Show Argo CD: port-forward, browser to localhost:8081, show synced app
 4. Show running app: curl http://localhost:8888 shows v1
 5. Change version: edit deployment.yaml in GitLab repo, commit, push
 6. Watch sync: Argo CD UI or kubectl get pods -n dev -w
 7. Verify change: curl http://localhost:8888 shows v2
 8. Bonus: Switch back to v1
