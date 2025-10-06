# End-to-End Flow and Cleanup Guide

This guide provides a complete walkthrough of the AWS Dedicated Hosts with Kubernetes demo, from initial setup to final cleanup.

## 🎯 Overview

This demo showcases intelligent Kubernetes scheduling across AWS Dedicated Hosts with overflow to default tenancy instances. The complete flow takes approximately 15-20 minutes.

## 📋 Prerequisites Checklist

Before starting, ensure you have:

- [ ] AWS CLI configured with appropriate permissions
- [ ] Terraform >= 1.0 installed
- [ ] kubectl >= 1.28 installed
- [ ] SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`
- [ ] AWS account with sufficient permissions for EC2, VPC, and Dedicated Hosts

## 🚀 Phase 1: Infrastructure Deployment (5-8 minutes)

### Step 1.1: Configure Terraform Variables
```bash
# Copy example configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit configuration (optional - defaults work for demo)
vim terraform/terraform.tfvars
```

### Step 1.2: Deploy AWS Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
cd ..
```

**Expected Output:**
- 2 Dedicated Hosts (us-west-2a, us-west-2b)
- 4 EC2 instances (1 master, 1 dedicated worker, 2 default workers)
- VPC with subnets across 2 AZs
- Security groups and networking

### Step 1.3: Verify Infrastructure
```bash
# Get node IPs
terraform -chdir=terraform output

# Test SSH connectivity to master
ssh -o ConnectTimeout=10 ec2-user@$(terraform -chdir=terraform output -raw master_public_ip)
```

## 🔧 Phase 2: Kubernetes Cluster Setup (3-5 minutes)

### Step 2.1: Wait for Nodes to be Ready
```bash
./scripts/wait-for-nodes.sh
```

### Step 2.2: Initialize Kubernetes Cluster
```bash
./scripts/setup-cluster.sh
```

**What this does:**
- Initializes kubeadm on master node
- Installs Calico networking
- Joins worker nodes to cluster
- Applies node taints and labels

### Step 2.3: Verify Cluster Status
```bash
# SSH to master and check nodes
ssh ec2-user@$(terraform -chdir=terraform output -raw master_public_ip)
kubectl get nodes -o wide
kubectl get nodes --show-labels
```

**Expected Output:**
```
NAME              STATUS   ROLES           AGE   VERSION
k8s-master        Ready    control-plane   5m    v1.28.x
k8s-dedicated-2   Ready    <none>          3m    v1.28.x
k8s-default-1     Ready    <none>          3m    v1.28.x
k8s-default-2     Ready    <none>          3m    v1.28.x
```

## 🎛️ Phase 3: Application Deployment (2-3 minutes)

### Step 3.1: Deploy Demo Applications
```bash
# SSH to master node
ssh ec2-user@$(terraform -chdir=terraform output -raw master_public_ip)

# Deploy Kubernetes resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/priority-class.yaml
kubectl apply -f k8s/demo-app.yaml
kubectl apply -f k8s/service.yaml
```

### Step 3.2: Deploy Management UIs
```bash
# Still on master node
kubectl apply -f k8s/dashboard.yaml
kubectl apply -f k8s/grafana.yaml
kubectl apply -f k8s/cluster-info.yaml
```

### Step 3.3: Verify Deployments
```bash
# Check pod placement
kubectl get pods -n demo -o wide
kubectl get pods -n kube-system -o wide

# Check services
kubectl get svc -n demo
kubectl get svc -n kube-system
```

## 📊 Phase 4: Demonstration and Testing (5 minutes)

### Step 4.1: Observe Initial Pod Placement
```bash
kubectl get pods -n demo -o wide
```

**Expected Behavior:**
- `demo-app-dedicated` pods prefer the dedicated host node
- `demo-app-overflow` pods deploy to default tenancy nodes

### Step 4.2: Test Scaling and Overflow
```bash
# Scale dedicated tier to trigger overflow
kubectl scale deployment demo-app-dedicated --replicas=8 -n demo

# Watch pod placement
kubectl get pods -n demo -o wide -w
```

**Expected Behavior:**
- First few pods land on dedicated host
- Additional pods overflow to default tenancy nodes

### Step 4.3: Access Management UIs
```bash
# Get master public IP
MASTER_IP=$(terraform -chdir=terraform output -raw master_public_ip)

echo "🎛️ Kubernetes Dashboard: https://$MASTER_IP:30443"
echo "📊 Grafana: http://$MASTER_IP:30300 (admin/admin123)"
echo "ℹ️ Cluster Info: http://$MASTER_IP:30080"
```

### Step 4.4: Test Load Balancer
```bash
# Test the demo application
curl http://$MASTER_IP:30080/api/health
```

## 🧹 Phase 5: Complete Cleanup

### Step 5.1: Destroy Kubernetes Resources (Optional)
```bash
# SSH to master node
ssh ec2-user@$(terraform -chdir=terraform output -raw master_public_ip)

# Remove all demo resources
kubectl delete namespace demo
kubectl delete -f k8s/dashboard.yaml
kubectl delete -f k8s/grafana.yaml
kubectl delete -f k8s/cluster-info.yaml
```

### Step 5.2: Destroy AWS Infrastructure
```bash
# From project root directory
cd terraform
terraform destroy -auto-approve
cd ..
```

### Step 5.3: Clean Up Local Files
```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform
rm -f terraform/terraform.tfstate*
rm -f terraform/.terraform.lock.hcl

# Remove any local SSH known_hosts entries (optional)
ssh-keygen -R $(terraform -chdir=terraform output -raw master_public_ip) 2>/dev/null || true
```

## 🔍 Troubleshooting Common Issues

### Issue: Terraform Apply Fails
**Symptoms:** Dedicated Host capacity not available
**Solution:**
```bash
# Try different AZ or instance type
vim terraform/terraform.tfvars
# Change availability_zones or instance_type
terraform apply -auto-approve
```

### Issue: Nodes Not Joining Cluster
**Symptoms:** Worker nodes stuck in NotReady state
**Solution:**
```bash
# Check node logs
ssh ec2-user@<NODE_IP>
sudo journalctl -u kubelet -f

# Restart kubelet if needed
sudo systemctl restart kubelet
```

### Issue: Pods Not Scheduling on Dedicated Hosts
**Symptoms:** All pods land on default tenancy nodes
**Solution:**
```bash
# Verify node labels and taints
kubectl get nodes --show-labels
kubectl describe node k8s-dedicated-2

# Check pod tolerations
kubectl describe pod <POD_NAME> -n demo
```

### Issue: Management UIs Not Accessible
**Symptoms:** Connection refused on management ports
**Solution:**
```bash
# Check service status
kubectl get svc -n kube-system
kubectl get pods -n kube-system

# Verify security group allows traffic
aws ec2 describe-security-groups --group-ids <SG_ID>
```

## 📈 Success Metrics

After successful deployment, you should see:

- [ ] 4 nodes in Ready state (1 master + 3 workers)
- [ ] Pods distributed across dedicated and default tenancy nodes
- [ ] Management UIs accessible via browser
- [ ] Demo application responding to health checks
- [ ] Scaling demonstrates overflow behavior

## 🎯 Next Steps

After completing this demo:

1. **Explore Scheduling**: Experiment with different pod priorities and node affinities
2. **Monitor Resources**: Use Grafana to observe resource utilization
3. **Test Resilience**: Simulate node failures and observe pod rescheduling
4. **Cost Analysis**: Review the cost breakdown in [COST-ANALYSIS.md](COST-ANALYSIS.md)
5. **Production Planning**: Adapt the architecture for your specific use case

## 📞 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review logs on the master node: `sudo journalctl -u kubelet -f`
3. Verify AWS resource limits and quotas
4. Ensure your AWS credentials have sufficient permissions

## 🔄 Automation Script

For a fully automated experience, use the provided scripts:

```bash
# Complete deployment
./quick_setup.sh

# Complete cleanup
./scripts/cleanup.sh
```

These scripts combine all the manual steps into automated workflows.