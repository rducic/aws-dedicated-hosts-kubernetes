# AWS Dedicated Hosts with Kubernetes - Deployment Guide

## Overview

This demo showcases how to deploy a self-managed Kubernetes cluster across AWS Dedicated Hosts in multiple Availability Zones, with intelligent pod placement that fills dedicated capacity first before overflowing to default tenancy instances.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS VPC (10.0.0.0/16)                   │
├─────────────────────────────┬───────────────────────────────────┤
│         AZ us-west-2a       │         AZ us-west-2b             │
│                             │                                   │
│ ┌─────────────────────────┐ │ ┌─────────────────────────────────┐ │
│ │    Dedicated Host 1     │ │ │    Dedicated Host 2             │ │
│ │    (m5.large)           │ │ │    (m5.large)                   │ │
│ │                         │ │ │                                 │ │
│ │  ┌─────────────────────┐│ │ │  ┌─────────────────────────────┐│ │
│ │  │   k8s-master        ││ │ │  │   k8s-dedicated-2           ││ │
│ │  │   (Control Plane)   ││ │ │  │   (Worker Node)             ││ │
│ │  │   Tainted           ││ │ │  │   Tainted                   ││ │
│ │  └─────────────────────┘│ │ │  └─────────────────────────────┘│ │
│ └─────────────────────────┘ │ └─────────────────────────────────┘ │
│                             │                                   │
│ ┌─────────────────────────┐ │ ┌─────────────────────────────────┐ │
│ │   Default Tenancy       │ │ │   Default Tenancy               │ │
│ │                         │ │ │                                 │ │
│ │  ┌─────────────────────┐│ │ │  ┌─────────────────────────────┐│ │
│ │  │   k8s-default-1     ││ │ │  │   k8s-default-2             ││ │
│ │  │   (Worker Node)     ││ │ │  │   (Worker Node)             ││ │
│ │  │   No Taints         ││ │ │  │   No Taints                 ││ │
│ │  └─────────────────────┘│ │ │  └─────────────────────────────┘│ │
│ └─────────────────────────┘ │ └─────────────────────────────────┘ │
└─────────────────────────────┴───────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl >= 1.28
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`
- jq (for JSON parsing in scripts)

### Required AWS Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:CreateInstanceProfile",
                "iam:AddRoleToInstanceProfile"
            ],
            "Resource": "*"
        }
    ]
}
```

## Deployment Steps

### 1. Infrastructure Setup

```bash
# Clone or navigate to project directory
cd DH-with-cubernetics

# Configure Terraform variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed (region, instance types, etc.)

# Deploy infrastructure
cd terraform
terraform init
terraform plan
terraform apply
cd ..
```

**What gets created:**
- VPC with 2 public subnets across 2 AZs
- 2 Dedicated Hosts (one per AZ)
- 4 EC2 instances (2 on dedicated hosts, 2 on default tenancy)
- Security groups allowing SSH and Kubernetes communication
- Internet Gateway and routing

### 2. Wait for Instance Initialization

```bash
# Wait for all nodes to complete their setup
./scripts/wait-for-nodes.sh
```

This script checks that kubeadm, kubectl, and Docker are installed on all nodes.

### 3. Kubernetes Cluster Setup

```bash
# Initialize cluster and join all nodes
./scripts/setup-cluster.sh
```

**What happens:**
- Initializes kubeadm on the first dedicated host (master)
- Installs Calico networking
- Joins all worker nodes to the cluster
- Copies kubeconfig locally

### 4. Manual Configuration (Due to User-Data Limitations)

Since the kubelet configuration in user-data didn't apply correctly, we manually configure:

```bash
# SSH to master node
ssh ec2-user@<MASTER_PUBLIC_IP>

# Add node labels
kubectl label node k8s-master tenancy=dedicated node-type=dedicated-host
kubectl label node k8s-dedicated-2 tenancy=dedicated node-type=dedicated-host
kubectl label node k8s-default-1 tenancy=default node-type=default-tenancy
kubectl label node k8s-default-2 tenancy=default node-type=default-tenancy

# Add taints to dedicated hosts
kubectl taint node k8s-master dedicated-host=true:NoSchedule
kubectl taint node k8s-dedicated-2 dedicated-host=true:NoSchedule
```

### 5. Deploy Demo Application

```bash
# Copy manifests to master node
scp -r k8s/ ec2-user@<MASTER_PUBLIC_IP>:~/

# SSH to master and deploy
ssh ec2-user@<MASTER_PUBLIC_IP>
kubectl apply -f k8s/namespace.yaml
sleep 2
kubectl apply -f k8s/priority-class.yaml
kubectl apply -f k8s/demo-app.yaml
kubectl apply -f k8s/service.yaml
```

## Verification and Testing

### Check Cluster Status

```bash
# SSH to master node
ssh ec2-user@<MASTER_PUBLIC_IP>

# View nodes with labels and taints
kubectl get nodes -o custom-columns="NAME:.metadata.name,TENANCY:.metadata.labels.tenancy,TYPE:.metadata.labels.node-type,TAINTS:.spec.taints[*].key"
```

Expected output:
```
NAME              TENANCY     TYPE              TAINTS
k8s-dedicated-2   dedicated   dedicated-host    dedicated-host
k8s-default-1     default     default-tenancy   <none>
k8s-default-2     default     default-tenancy   <none>
k8s-master        dedicated   dedicated-host    dedicated-host,node-role.kubernetes.io/control-plane
```

### View Pod Distribution

```bash
# Check pod placement
kubectl get pods -n demo -o wide

# View by tier
kubectl get pods -n demo -l tier=dedicated -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName"
kubectl get pods -n demo -l tier=overflow -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName"
```

### Test Scaling and Overflow

```bash
# Scale dedicated tier to force overflow
kubectl scale deployment demo-app-dedicated --replicas=12 -n demo

# Wait and check distribution
sleep 10
kubectl get pods -n demo -o wide

# Scale even more to see additional overflow
kubectl scale deployment demo-app-dedicated --replicas=20 -n demo
```

## Key Components Explained

### Node Affinity and Scheduling

The demo uses several Kubernetes scheduling features:

1. **Node Affinity**: Pods prefer dedicated hosts but can schedule elsewhere
2. **Taints and Tolerations**: Dedicated hosts are tainted to prevent unwanted workloads
3. **Priority Classes**: Higher priority for dedicated host workloads

### Priority Classes

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: dedicated-host-priority
value: 1000
description: "Priority class for pods that should run on dedicated hosts"
```

### Pod Tolerations

```yaml
tolerations:
- key: "dedicated-host"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

### Node Affinity Rules

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: tenancy
          operator: In
          values: ["dedicated"]
```

## Troubleshooting

### Common Issues

1. **Kubeconfig Connection Timeout**
   - Issue: Local kubectl can't connect to private IP
   - Solution: Use SSH to master node or update security groups for port 6443

2. **Pods Not Scheduling on Dedicated Hosts**
   - Check node labels: `kubectl get nodes --show-labels`
   - Check taints: `kubectl describe nodes`
   - Verify tolerations in pod specs

3. **User-Data Script Failures**
   - Check cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
   - Verify Kubernetes repository access
   - Check hostname format (no trailing dashes)

### Debugging Commands

```bash
# Check node status
kubectl get nodes -o wide

# View events
kubectl get events -n demo --sort-by='.lastTimestamp'

# Check pod scheduling
kubectl describe pod <POD_NAME> -n demo

# View resource usage
kubectl top nodes
kubectl top pods -n demo
```

## Cleanup

```bash
# Remove all resources
./scripts/cleanup.sh
```

This will:
- Delete Kubernetes resources
- Destroy Terraform infrastructure
- Remove local kubeconfig

## Cost Considerations

- **Dedicated Hosts**: ~$1,000-2,000/month per host (depending on instance family)
- **EC2 Instances**: Included in dedicated host cost
- **Data Transfer**: Minimal for this demo
- **EBS Storage**: ~$0.10/GB/month for root volumes

## Security Notes

- Security group allows SSH (port 22) from anywhere for demo purposes
- Kubernetes API (port 6443) should be restricted in production
- Consider using bastion hosts for SSH access
- Enable VPC Flow Logs for network monitoring

## Production Considerations

1. **High Availability**: Deploy across 3+ AZs
2. **Load Balancing**: Use AWS ALB for ingress
3. **Monitoring**: Implement CloudWatch, Prometheus
4. **Backup**: Regular etcd backups
5. **Security**: Restrict security groups, use IAM roles
6. **Networking**: Consider private subnets with NAT gateways