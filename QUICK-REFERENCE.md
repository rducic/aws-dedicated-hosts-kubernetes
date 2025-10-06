# 🚀 Quick Reference Guide

## 📍 **Get Public IP Addresses**

### **Master Node IP (for Management UIs)**
```bash
# Get master node public IP
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
echo "Master IP: $MASTER_IP"

# Alternative method
terraform -chdir=terraform output dedicated_node_ips
```

### **All Node IPs**
```bash
# Get all dedicated host IPs
terraform -chdir=terraform output dedicated_node_ips

# Get all default tenancy IPs  
terraform -chdir=terraform output default_node_ips

# Get all IPs in one command
echo "Dedicated Hosts:" && terraform -chdir=terraform output dedicated_node_ips
echo "Default Tenancy:" && terraform -chdir=terraform output default_node_ips
```

## 🎛️ **Access Management UIs**

### **Kubernetes Dashboard**
```bash
# Get master IP and open dashboard
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
echo "Dashboard: https://$MASTER_IP:30443"

# Generate access token
ssh ec2-user@$MASTER_IP "kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
```

### **Grafana**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
echo "Grafana: http://$MASTER_IP:30300"
echo "Username: admin"
echo "Password: admin123"
```

### **Cluster Info**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
echo "Cluster Info: http://$MASTER_IP:30080"
```

## 🔧 **Common Commands**

### **Check Cluster Status**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

# View nodes
ssh ec2-user@$MASTER_IP "kubectl get nodes -o wide"

# View pods distribution
ssh ec2-user@$MASTER_IP "kubectl get pods -n demo -o wide"

# Check node labels and taints
ssh ec2-user@$MASTER_IP "kubectl get nodes -o custom-columns='NAME:.metadata.name,TENANCY:.metadata.labels.tenancy,TAINTS:.spec.taints[*].key'"
```

### **Scale Applications**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

# Scale dedicated tier to test overflow
ssh ec2-user@$MASTER_IP "kubectl scale deployment demo-app-dedicated --replicas=12 -n demo"

# Scale back down
ssh ec2-user@$MASTER_IP "kubectl scale deployment demo-app-dedicated --replicas=8 -n demo"
```

### **Monitor Resources**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

# Check resource usage (if metrics server is working)
ssh ec2-user@$MASTER_IP "kubectl top nodes"
ssh ec2-user@$MASTER_IP "kubectl top pods -n demo"

# View events
ssh ec2-user@$MASTER_IP "kubectl get events -n demo --sort-by='.lastTimestamp'"
```

## 🛠️ **Troubleshooting**

### **SSH Connection Issues**
```bash
# Test SSH connectivity
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
ssh -o ConnectTimeout=10 ec2-user@$MASTER_IP "echo 'Connection successful'"

# Check security group rules
aws ec2 describe-security-groups --region us-west-2 --group-ids $(aws ec2 describe-instances --region us-west-2 --filters "Name=tag:Name,Values=k8s-*" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
```

### **UI Access Issues**
```bash
# Check if services are running
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
ssh ec2-user@$MASTER_IP "kubectl get svc -A | grep -E '(dashboard|grafana|cluster-info)'"

# Test port connectivity
curl -s -o /dev/null -w "%{http_code}" http://$MASTER_IP:30080  # Should return 200
curl -s -o /dev/null -w "%{http_code}" http://$MASTER_IP:30300  # Should return 200
curl -s -o /dev/null -w "%{http_code}" -k https://$MASTER_IP:30443  # Should return 200
```

### **Pod Scheduling Issues**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

# Check pending pods
ssh ec2-user@$MASTER_IP "kubectl get pods -A --field-selector=status.phase=Pending"

# Describe problematic pod
ssh ec2-user@$MASTER_IP "kubectl describe pod <pod-name> -n <namespace>"

# Check node capacity
ssh ec2-user@$MASTER_IP "kubectl describe nodes"
```

## 💰 **Cost Monitoring**

### **Quick Cost Check**
```bash
# View current AWS costs (requires AWS CLI)
aws ce get-cost-and-usage --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE

# Check dedicated host utilization
aws ec2 describe-hosts --region us-west-2 --query 'Hosts[*].[HostId,InstanceType,AvailabilityZone,Instances[*].InstanceId]' --output table
```

## 🧹 **Cleanup**

### **Complete Cleanup**
```bash
# Remove all resources
./scripts/cleanup.sh

# Verify cleanup
terraform -chdir=terraform show
aws ec2 describe-instances --region us-west-2 --filters "Name=tag:Name,Values=k8s-*" --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' --output table
```

### **Partial Cleanup (Keep Infrastructure)**
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

# Remove demo applications only
ssh ec2-user@$MASTER_IP "kubectl delete namespace demo"
ssh ec2-user@$MASTER_IP "kubectl delete namespace monitoring"
ssh ec2-user@$MASTER_IP "kubectl delete namespace kubernetes-dashboard"
```

---

## 📋 **Environment Variables**

For convenience, set these in your shell:

```bash
# Add to ~/.bashrc or ~/.zshrc
export MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]' 2>/dev/null)
export CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name 2>/dev/null)

# Usage examples:
ssh ec2-user@$MASTER_IP "kubectl get nodes"
echo "Dashboard: https://$MASTER_IP:30443"
```