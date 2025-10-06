# AWS Dedicated Hosts with Kubernetes - Execution Guide

## 🎯 Architecture Overview

This demo creates a Kubernetes cluster with:
- **1 Master Node** (default tenancy for cost optimization)
- **2 Dedicated Host Worker Nodes** (k8s-dedicated-1, k8s-dedicated-2)
- **2 Default Tenancy Worker Nodes** (k8s-default-1, k8s-default-2)
- **Spillover behavior** from dedicated hosts to default tenancy

## 📋 Prerequisites

1. AWS CLI configured with appropriate permissions
2. Terraform installed
3. kubectl installed
4. SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

## 🚀 Step-by-Step Execution

### Step 1: Deploy Infrastructure
```bash
chmod +x scripts/*.sh
./scripts/01-deploy-infrastructure.sh
```

**What this does:**
- Creates VPC, subnets, security groups
- Provisions 2 dedicated hosts
- Launches 5 EC2 instances (1 master + 2 dedicated + 2 default)
- Initializes master node with Kubernetes

**Expected output:**
- Infrastructure deployed
- Master node IP address
- All instance IPs listed

### Step 2: Set Up Kubernetes Cluster
```bash
./scripts/02-setup-cluster.sh
```

**What this does:**
- Joins all worker nodes to the cluster
- Applies taints to dedicated host nodes
- Sets up local kubectl access
- Configures node labels and scheduling

**Expected output:**
```
NAME              STATUS   ROLES           AGE   VERSION
k8s-master        Ready    control-plane   5m    v1.28.15
k8s-dedicated-1   Ready    <none>          3m    v1.28.15
k8s-dedicated-2   Ready    <none>          3m    v1.28.15
k8s-default-1     Ready    <none>          2m    v1.28.15
k8s-default-2     Ready    <none>          2m    v1.28.15
```

### Step 3: Deploy Demo Workloads
```bash
./scripts/03-deploy-workloads.sh
```

**What this does:**
- Deploys applications with node affinity for dedicated hosts
- Creates spillover workloads
- Deploys management UIs (Dashboard, Grafana, Cluster Info)
- Shows initial pod distribution

**Expected output:**
- Pods scheduled on dedicated hosts first
- Some pods on default tenancy nodes (spillover)

### Step 4: Generate CPU Load
```bash
./scripts/04-generate-load.sh
```

**What this does:**
- Scales up applications to increase load
- Generates CPU-intensive workloads on dedicated hosts
- Monitors resource utilization in real-time
- Demonstrates high utilization (target: 80-100%)

**Expected output:**
```
NAME              CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
k8s-dedicated-1   1800m        90%      800Mi           10%          
k8s-dedicated-2   1900m        95%      850Mi           11%          
k8s-default-1     1200m        60%      600Mi           8%          
k8s-default-2     1100m        55%      550Mi           7%          
```

### Step 5: Monitor and Analyze
```bash
# Check resource utilization
kubectl top nodes

# Check pod distribution
kubectl get pods -n demo -o wide | grep Running | awk '{print $7}' | sort | uniq -c

# Access management UIs
echo "Kubernetes Dashboard: https://$(terraform output -raw master_public_ip):30443"
echo "Grafana: http://$(terraform output -raw master_public_ip):30300"
echo "Cluster Info: http://$(terraform output -raw master_public_ip):30080"
```

### Step 6: Cleanup (Optional)
```bash
./scripts/05-cleanup.sh
```

## 🎯 Expected Demonstration Results

### ✅ Success Criteria

1. **Proper Node Configuration:**
   - 2 dedicated host worker nodes with taints
   - 2 default tenancy worker nodes without taints
   - All nodes joined and ready

2. **Spillover Behavior:**
   - Pods prefer dedicated hosts (node affinity)
   - When dedicated capacity reached, pods spill to default tenancy
   - No pods stuck in pending state due to scheduling

3. **High Utilization:**
   - Dedicated hosts: 80-100% CPU utilization
   - Default tenancy: Variable utilization based on spillover
   - Memory utilization: 10-20%

4. **Cost Optimization:**
   - Master on default tenancy (cost savings)
   - Dedicated hosts fully utilized (ROI maximized)
   - Default tenancy handles overflow efficiently

## 🔧 Troubleshooting

### Issue: Nodes not joining cluster
```bash
# Check master node status
ssh -i ~/.ssh/id_rsa ec2-user@<master-ip> "kubectl get nodes"

# Get new join command
ssh -i ~/.ssh/id_rsa ec2-user@<master-ip> "sudo kubeadm token create --print-join-command"

# Manually join a node
ssh -i ~/.ssh/id_rsa ec2-user@<worker-ip> "sudo <join-command> --node-name=<node-name>"
```

### Issue: Pods not scheduling on dedicated hosts
```bash
# Check node taints and labels
kubectl describe nodes

# Check pod events
kubectl describe pod <pod-name> -n demo

# Remove taint temporarily for testing
kubectl taint node k8s-dedicated-1 dedicated-host=true:NoSchedule-
```

### Issue: Low CPU utilization
```bash
# Manually generate CPU load
kubectl exec -n demo <pod-name> -- /bin/sh -c 'while true; do :; done' &

# Scale up applications
kubectl scale deployment demo-app-dedicated --replicas=20 -n demo
```

## 📊 Monitoring Commands

```bash
# Real-time resource monitoring
watch kubectl top nodes

# Pod distribution
kubectl get pods -n demo -o wide

# Events
kubectl get events -n demo --sort-by='.lastTimestamp'

# Detailed node information
kubectl describe node k8s-dedicated-1
```

## 💰 Cost Analysis

- **Dedicated Hosts:** $4,174/month each (2 hosts = $8,348/month)
- **Default Tenancy:** Pay-per-use for spillover capacity
- **Master Node:** ~$50/month (default tenancy)
- **Total:** ~$8,400/month with optimized spillover architecture

## 🎉 Success Metrics

- ✅ 5 nodes in Ready state
- ✅ Dedicated hosts at 80%+ CPU utilization
- ✅ Spillover pods running on default tenancy
- ✅ Management UIs accessible
- ✅ No pending pods due to scheduling issues