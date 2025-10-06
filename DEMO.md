# Demo Walkthrough

This guide walks through the complete demo of AWS Dedicated Hosts with Kubernetes.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform installed
- kubectl installed
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`
- jq installed for JSON parsing

## Step 1: Deploy Infrastructure

```bash
# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars

# Initialize and apply Terraform
cd terraform
terraform init
terraform apply
cd ..
```

This creates:
- VPC with 2 public subnets across 2 AZs
- 2 Dedicated Hosts (one per AZ)
- 4 EC2 instances (2 on dedicated hosts, 2 on default tenancy)
- Security groups and networking

## Step 2: Set Up Kubernetes Cluster

```bash
./scripts/setup-cluster.sh
```

This script:
- Initializes kubeadm on the first dedicated host
- Joins all other nodes to the cluster
- Installs Calico networking
- Configures node labels and taints

## Step 3: Deploy Demo Application

```bash
./scripts/deploy-demo.sh
```

This deploys:
- Priority classes for scheduling preference
- Demo application with 8 replicas preferring dedicated hosts
- Overflow application with 4 replicas for default tenancy
- Load balancer service

## Step 4: Test Scaling Behavior

```bash
./scripts/test-scaling.sh
```

This demonstrates:
- Scaling dedicated tier to fill dedicated hosts
- Overflow behavior when dedicated hosts are full
- Pod distribution across node types

## Expected Behavior

1. **Initial Deployment**: 8 pods deploy to dedicated hosts first
2. **Scaling Up**: Additional pods fill remaining capacity on dedicated hosts
3. **Overflow**: When dedicated hosts are full, new pods schedule on default tenancy nodes
4. **Priority**: Dedicated host pods have higher priority and will preempt default tenancy pods if needed

## Monitoring Commands

```bash
# Check node labels and taints
kubectl get nodes -o custom-columns="NAME:.metadata.name,TENANCY:.metadata.labels.tenancy,TAINTS:.spec.taints[*].key"

# View pod distribution
kubectl get pods -n demo -o wide

# Check resource usage
kubectl top nodes
kubectl top pods -n demo

# View events
kubectl get events -n demo --sort-by='.lastTimestamp'
```

## Cleanup

```bash
./scripts/cleanup.sh
```

This removes all Kubernetes resources and destroys the AWS infrastructure.

## Key Concepts Demonstrated

- **Node Affinity**: Preferential scheduling to dedicated hosts
- **Taints and Tolerations**: Dedicated hosts tainted to prevent unwanted pods
- **Priority Classes**: Higher priority for dedicated host workloads
- **Resource Limits**: Controlled resource allocation per pod
- **Multi-AZ Deployment**: Distributed across availability zones
- **Graceful Overflow**: Automatic fallback to default tenancy when needed