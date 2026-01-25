# Conceitos Fundamentais do Kubernetes

> Kubernetes agenda Pods em Nodes, dentro de um Cluster, organizados por Namespaces.

## Visão geral (definições curtas)

- **Container**: processo isolado que executa uma aplicação
- **Pod**: menor unidade gerenciável do Kubernetes (contém um ou mais containers)  
- **Node**: máquina (VM) que executa pods
- **Cluster**: conjunto de nodes gerenciados pelo Kubernetes  
- **Control Plane**: conjunto de componentes que controlam e coordenam o cluster  
- **Namespace**: divisão lógica dentro de um cluster  

---

## 1️⃣ Container

### O que é
Um **container** é um processo isolado que executa uma aplicação junto com suas dependências.  
Normalmente é criado a partir de um **Dockerfile**.

### Características
- Leve e rápido  
- Compartilha o kernel do sistema operacional  
- Imutável  
- Ideal para empacotar aplicações  

### Importante
➡️ Kubernetes **não gerencia containers diretamente**  
➡️ Ele gerencia **Pods**

---

## 2️⃣ Pod

### O que é
Um **Pod** é a menor unidade que o Kubernetes pode criar, escalar e destruir.

Um Pod pode conter:
- **1 container** (caso mais comum)  
- **Vários containers** (casos específicos)

### Por que o Kubernetes usa Pods?
Porque alguns containers precisam:
- Compartilhar rede  
- Compartilhar volumes  
- Ter o mesmo ciclo de vida  

### Quando NÃO usar múltiplos containers no mesmo Pod
- Serviços independentes  
- Aplicações que precisam escalar separadamente  

> ❗ Isso é considerado um **anti-padrão**.

---

## 3️⃣ Node

### O que é
Um **Node** é a máquina (VM ou física) onde os Pods são executados.

### O que roda em um Node
- Container runtime (Docker, containerd)  
- kubelet  
- kube-proxy  

### Função
- Executar Pods  
- Reportar estado ao cluster  
- Gerenciar recursos locais  

---

## 4️⃣ Cluster

### O que é
Um **Cluster Kubernetes** é um conjunto de Nodes controlados por um **Control Plane**.

### Função do Cluster
- Agrupar Nodes
- Executar aplicações distribuídas
- Fornecer alta disponibilidade e escalabilidade

---

## 5️⃣ Control Plane

### O que é
O **Control Plane** é o **cérebro do Cluster Kubernetes**.  
Ele **não executa aplicações**, mas **controla e coordena todo o funcionamento do cluster**.

### Principais responsabilidades
- Receber comandos (`kubectl`, APIs, automações)
- Decidir **em qual Node** cada Pod deve rodar
- Garantir que o **estado desejado** seja mantido
- Detectar falhas e **recriar recursos automaticamente**

### Componentes principais
- API Server  
- Scheduler  
- Controllers  
- etcd  

### Observação
- O Control Plane **gerencia**, mas não executa Pods
- Em clusters gerenciados (EKS, GKE, AKS), ele é **abstraído do usuário**

---

## 6️⃣ Namespace

### O que é
Um **Namespace** é uma **divisão lógica dentro de um Cluster**.

Ele não cria isolamento físico, apenas organizacional.

### Para que serve
- Separar ambientes (dev, staging, prod)  
- Isolar times  
- Organizar recursos  
- Evitar conflitos de nomes  

### Exemplos comuns
- `default`  
- `kube-system`  
- `dev`  
- `prod`  
- `argocd`  

---

### Importante sobre Namespaces
- Pods em namespaces diferentes **podem rodar no mesmo Node**  
- Namespaces **não isolam CPU ou memória por padrão**  
- Isolamento real exige:
  - `ResourceQuota`  
  - `LimitRange`  
  - RBAC (Role-Based Access Control): sistema de controle de permissões do Kubernetes.

---

## Relação entre os conceitos

Estrutura conceitual:

- **Cluster**
  - **Control Plane**
  - **Node**
    - **Pod**
      - **Container**

Os **Namespaces** organizam Pods, Services e Deployments **dentro do Cluster**.

---

## Comparação rápida

| Conceito | O que é | Escala | Gerenciado por |
|--------|--------|--------|---------------|
| Container | Processo isolado | ❌ | Runtime |
| Pod | Unidade mínima | ✅ | Kubernetes |
| Node | Máquina | ❌ | Kubernetes / Cloud |
| Control Plane | Controle e coordenação | ❌ | Kubernetes |
| Cluster | Conjunto de nodes | ❌ | Kubernetes |
| Namespace | Organização lógica | ❌ | Kubernetes |

---

## Regras de ouro

- Kubernetes escala Pods, não containers  
- Pods são descartáveis  
- Nodes são substituíveis  
- O Control Plane decide, os Nodes executam  
- Cluster é o limite físico  
- Namespace é o limite lógico  

===

# K3S e K3D

- K3S: Kubernetes leve para produção ou dev.
- K3D: K3S dentro de Docker, perfeito para testes locais.

## K3S

- **O que é:** Distribuição leve do Kubernetes, feita pela Rancher, ideal para IoT, desenvolvimento local ou clusters pequenos.
- **Características principais:**
  - Binário único e pequeno (~50 MB)
  - Menos dependências, fácil de instalar
  - Inclui Containerd como runtime padrão
  - Suporta ARM (Raspberry Pi, etc.)
  - Control Plane e Node podem rodar na mesma máquina


## K3D

- **O que é:** Ferramenta que roda clusters K3S dentro de containers Docker.
- **Quando usar:** Para desenvolvimento local rápido, testes de CI/CD ou experimentos com múltiplos clusters.
- **Vantagens:**
  - Criação de clusters em segundos
  - Fácil teardown e recriação
  - Simula clusters de múltiplos nodes em uma máquina




## ArgoCD

**O que é:**

- Ferramenta de Continuous Delivery (CD) para Kubernetes
- Baseada em GitOps, ou seja, o estado desejado do cluster é definido em repositórios Git

> 💡 Pense no ArgoCD como um “Git para Kubernetes”: ele garante que o que está no cluster seja exatamente o que está no Git.

**Como funciona:**

1. O desenvolvedor atualiza o código e/ou manifestos Kubernetes no Git
2. ArgoCD detecta a mudança e aplica automaticamente no cluster
3. Garante que o estado real do cluster corresponda ao estado desejado no Git

**Benefícios:**

- Automatização total do deploy
- Auditoria fácil (tudo versionado no Git)
- Rollback simples para versões anteriores
- Multi-cluster: gerencia vários clusters a partir de um único ArgoCD

**Componentes principais:**

- **Application:** objeto que representa um app ou serviço
- **Repository:** onde ficam os manifests Git
- **Sync:** mecanismo que aplica alterações do Git no cluster
