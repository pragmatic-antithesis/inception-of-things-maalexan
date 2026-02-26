# Part One - P1
## Part 1.1 - Initial setup

### Start the VMs
>vagrant up
### Starts both virtual machines defined in Vagrantfile

### Check VM status
>vagrant status

### **Expected output:** <br> Both VMs as "running"

### SSH into Server (controller)
>vagrant ssh inwagnerS`
### Connects to the controller node (192.168.56.***110***)

### SSH into Worker
>vagrant ssh inwagnerW`
### Connects to the worker node (192.168.56.***111***)

## Part 1.2 - Network

### Check IP configuration (on both VMs)
>ip a | grep eth1
### **Expected output:** <br> Interface with IP *192.168.56.110* (on inwagnerS) or *192.168.56.111* (on inwagnerSW)

### Test connectivity between VMs (from inwagnerS)
>ping -c 3 192.168.56.111
### **Expected output:** <br> 3 successful ping responses

## Part 1.3 - k3s Status 

### On Server (inwagnerS) - Check node status
>sudo kubectl get nodes
### Expected output: 
```
NAME        STATUS  ROLES                 AGE   VERSION  
inwagnerS   Ready   control-plane,master  XXm   vX.XX  
inwagnerSW  Ready   <none>                XXm   vX.XX
```

### Check all pods
>sudo kubectl get pods -A
### **Expected output:** <br> List of system pods all in "Running" status

### Check K3s service status (on inwagnerS/inwagnerSW)
>  inwagnerS:
>>sudo rc-service k3s status<br>

> inwagnerSW:
>>sudo rc-service k3s-agent status

### **Expected output:** <br> "active (running)" for each service


## Part 1.4 - Basic Deployment
### Create a test deployment (from inwagnerS)
>sudo kubectl create deployment nginx --image=nginx

### Check deployment
>sudo kubectl get deployments
### **Expected output:** <br> nginx deployment with 1/1 ready

### Expose the deployment
>sudo kubectl expose deployment nginx --port=8080 --type=NodePort

### Get service info
>sudo kubectl get svc
### **Expected output:** <br> nginx service with assigned port

### Test the service (from inwagnerS)
>curl http://localhost:\<NODEPORT\>
### **Expected output:** <br> Welcome to nginx HTML page
