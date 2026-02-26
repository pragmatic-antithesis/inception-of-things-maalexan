# Part One - P1
## Part 1.1 - Initial setup

### Start the VMs
>`vagrant up`
### Starts both virtual machines defined in Vagrantfile

### Check VM status
>`vagrant status`

### **Expected output:**
```
Both VMs as "running"
```

### SSH into Server (controller)
>`vagrant ssh inwagnerS`
### Connects to the controller node (192.168.56.***110***)

### SSH into Worker
>`vagrant ssh inwagnerW`
### Connects to the worker node (192.168.56.***111***)

## Part 1.2 - Network

### Check IP configuration (on both VMs)
>`ip a | grep eth1`
### **Expected output:**
```
Interface with IP 192.168.56.110 (inwagnerS) or 192.168.56.111 (inwagnerSW)
```

### Test connectivity between VMs (from inwagnerS)
>`ping -c 3 192.168.56.111`
### **Expected output:**
```
3 successful ping responses
```

## Part 1.3 - k3s Status 

### On Server (inwagnerS) - Check node status
>`sudo kubectl get nodes`
### Expected output: 
```
NAME        STATUS  ROLES                 AGE   VERSION  
inwagnerS   Ready   control-plane,master  XXm   vX.XX  
inwagnerSW  Ready   <none>                XXm   vX.XX
```

### Check all pods
>`sudo kubectl get pods -A`
### **Expected output:**
```
List of system pods all in "Running" status
```

### Check K3s service status (on inwagnerS/inwagnerSW)
>  inwagnerS:
>>`sudo rc-service k3s status`

> inwagnerSW:
>>`sudo rc-service k3s-agent status`

### **Expected output:**
```
"active (running)" for each service
```

## Part 1.4 - Basic Deployment
### Create a test deployment (from inwagnerS)
>`sudo kubectl create deployment nginx --image=nginx`

### Check deployment
>`sudo kubectl get deployments`
### **Expected output:**
```
nginx deployment with 1/1 ready
```

### Expose the deployment
>`sudo kubectl expose deployment nginx --port=8080 --type=NodePort`

### Get service info
>`sudo kubectl get svc`
### **Expected output:**
```
nginx service with assigned port
```

### Test the service (from inwagnerS)
>`curl -v http://localhost:<NODEPORT>`
### **Expected output:**
```
Welcome to nginx HTML page
```

# Part Two - P2
## Part 2.1 - Initial setup

### Start the VMs
>`vagrant up`
### Starts both virtual machines defined in Vagrantfile

### Check VM status
>`vagrant status`

### **Expected output:**
```
inwagnerS as "running"
```

### SSH into Server (controller)
>`vagrant ssh inwagnerS`
### Connects to the controller node (192.168.56.***110***)

### Check K3s status
>`sudo rc-service k3s status`

### **Expected output:**
```
 * status: started
```

## Part 2.2 - Application Status

### Check all deployments
>`sudo kubectl get deployments -A`
### **Expected output:**
```
app1, app2, app3 deployed
```

### Check app2 has 3 replicas
>`sudo kubectl get deployment <app2>`
### **Expected output:** 
```
 3/3 ready replicas
```

### Check all pods
>`sudo kubectl get pods -o wide`
### **Expected output:**
```
app1: 1 pod running
app2: 3 pods running on different nodes/replicas
app3: 1 pod running
```
### Check services
>`sudo kubectl get svc`
### **Expected output:**
```
The three services (app1, app2, app3) with their cluster IPs
```

## Part 2.3 - Ingress

### Check Ingress resource
>`sudo kubectl get ingress`
### **Expected output:**
```
Shows ingress with rules for app1.com, app2.com, and default backend
```

### Ingress detailed rules
>`sudo kubectl describe ingress`
### **Expected output:**
```
Detailed routing rules showing:
# - app1.com -> app1 service
# - app2.com -> app2 service
# - * (default) -> app3 service
```


## Part 2.4 - Application Usage
### From host machine (or within VM with curl)

## Test app1
>`curl -H "Host: app1.com" http://192.168.56.110`
### **Expected output:**
```
Content from app1
```

## Test app2
>`curl -H "Host: app2.com" http://192.168.56.110`
### **Expected output:**
```
Content from app2
```

## Test default (app3)
>`curl http://192.168.56.110`
### **Expected output:**
```
Content from app3
```

## Test with different host
>`curl -H "Host: anything.com" http://192.168.56.110`
### **Expected output:**
```
Content from app3 (default)
```

## Alternatively, from host machine
>`echo '192.168.56.110    app1.com app2.com app3.com' | sudo tee -a /etc/hosts/`
### **From browser:**
```
    http://app1.com - app1

    http://app2.com - app2 (with load balancing between 3 replicas)

    http://app3.com - app3

    http://192.168.56.110 - default (app3)
```

