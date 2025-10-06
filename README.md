# AWS Dedicated Hosts with Kubernetes Demo

This repo showcases how to deploy a self-managed Kubernetes cluster across AWS Dedicated Hosts in multiple Availability Zones, with intelligent pod placement that fills dedicated capacity first before overflowing to default tenancy instances.

## 🎯 What This Demo Shows

1. **Dedicated Host Utilization**: Deploy workloads on single-tenant hardware for compliance
2. **Intelligent Scheduling**: Pods prefer dedicated hosts but gracefully overflow to shared infrastructure
3. **Multi-AZ Resilience**: Distributed deployment across availability zones
4. **Cost Optimization**: Hybrid approach balancing compliance needs with cost efficiency

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS VPC (10.0.0.0/16)                    │
├─────────────────────────────┬───────────────────────────────────┤
│         AZ us-west-2a       │         AZ us-west-2b             │
│                             │                                   │
│ ┌─────────────────────────┐ │ ┌─────────────────────────────────┐ │
│ │    Dedicated Host 1     │ │ │    Dedicated Host 2             │ │
│ │    ┌─────────────────┐  │ │ │  ┌─────────────────────────────┐│ │
│ │    │   k8s-master    │  │ │ │  │   k8s-dedicated-2           ││ │
│ │    │   (Tainted)     │  │ │ │  │   (Tainted)                 ││ │
│ │    └─────────────────┘  │ │ │  └─────────────────────────────┘│ │
│ └─────────────────────────┘ │ └─────────────────────────────────┘ │
│                             │                                   │
│ ┌─────────────────────────┐ │ ┌─────────────────────────────────┐ │
│ │   Default Tenancy       │ │ │   Default Tenancy               │ │
│ │    ┌─────────────────┐  │ │ │  ┌─────────────────────────────┐│ │
│ │    │  k8s-default-1  │  │ │ │  │   k8s-default-2             ││ │
│ │    │  (Overflow)     │  │ │ │  │   (Overflow)                ││ │
│ │    └─────────────────┘  │ │ │  └─────────────────────────────┘│ │
│ └─────────────────────────┘ │ └─────────────────────────────────┘ │
└─────────────────────────────┴───────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl >= 1.28
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

### Deployment Steps

1. **Deploy Infrastructure**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   cd terraform && terraform init && terraform apply && cd ..
   ```

2. **Wait for Nodes**
   ```bash
   ./scripts/wait-for-nodes.sh
   ```

3. **Setup Kubernetes Cluster**
   ```bash
   ./scripts/setup-cluster.sh
   ```

4. **Deploy Demo Application**
   ```bash
   # SSH to master node (get IP from terraform output)
   ssh ec2-user@<MASTER_PUBLIC_IP>
   
   # Deploy applications
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/priority-class.yaml
   kubectl apply -f k8s/demo-app.yaml
   kubectl apply -f k8s/service.yaml
   ```

5. **Deploy Management UIs**
   ```bash
   ./scripts/deploy-management-ui.sh
   ```

6. **Test Scaling**
   ```bash
   # Scale to see overflow behavior
   kubectl scale deployment demo-app-dedicated --replicas=12 -n demo
   kubectl get pods -n demo -o wide
   ```

## 📊 Demo Results

After deployment, you'll see:

- **4 Kubernetes nodes**: 1 master + 1 dedicated worker + 2 default workers
- **Intelligent pod placement**: Dedicated tier pods prefer dedicated hosts
- **Graceful overflow**: When dedicated capacity is full, pods deploy to default tenancy
- **Multi-AZ distribution**: Workloads spread across availability zones

Example pod distribution:
```
Dedicated Tier Pods (prefer dedicated hosts):
NAME                                  NODE
demo-app-dedicated-5fc87cf5cc-4kb5m   k8s-dedicated-2
demo-app-dedicated-5fc87cf5cc-8thbm   k8s-dedicated-2
demo-app-dedicated-5fc87cf5cc-9fm77   k8s-default-2      ← Overflow
demo-app-dedicated-5fc87cf5cc-dx5qn   k8s-dedicated-2

Overflow Tier Pods (default tenancy):
NAME                                NODE
demo-app-overflow-5f8bd76b8-4vxpw   k8s-default-1
demo-app-overflow-5f8bd76b8-czsdp   k8s-default-1
```

## 🎛️ Management UIs

After deployment, access these management interfaces:

- **🎛️ Kubernetes Dashboard**: `https://<MASTER_PUBLIC_IP>:30443` (Token required)
- **📊 Grafana**: `http://<MASTER_PUBLIC_IP>:30300` (admin/admin123)
- **ℹ️ Cluster Info**: `http://<MASTER_PUBLIC_IP>:30080` (Demo overview)

**Get Master Public IP**: `terraform -chdir=terraform output dedicated_node_ips`

See [MANAGEMENT-UIS.md](MANAGEMENT-UIS.md) for detailed access instructions and features.

## 📁 Project Structure

```
├── terraform/              # AWS infrastructure
│   ├── main.tf             # Core infrastructure resources
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output values
│   ├── user-data-*.sh      # EC2 initialization scripts
│   └── terraform.tfvars    # Configuration values
├── k8s/                    # Kubernetes manifests
│   ├── namespace.yaml      # Demo namespace
│   ├── priority-class.yaml # Scheduling priorities
│   ├── demo-app.yaml       # Sample applications
│   ├── service.yaml        # Load balancer service
│   ├── dashboard.yaml      # Kubernetes Dashboard
│   ├── grafana.yaml        # Grafana monitoring
│   └── cluster-info.yaml   # Demo info web interface
├── scripts/                # Automation scripts
│   ├── setup-cluster.sh    # Kubernetes cluster setup
│   ├── wait-for-nodes.sh   # Node readiness check
│   ├── deploy-demo.sh      # Application deployment
│   ├── deploy-management-ui.sh # Management UIs deployment
│   ├── test-scaling.sh     # Scaling demonstration
│   └── cleanup.sh          # Resource cleanup
└── docs/                   # Documentation
    ├── DEPLOYMENT-GUIDE.md # Detailed deployment guide
    ├── ARCHITECTURE.md     # Technical architecture
    ├── LESSONS-LEARNED.md  # Implementation insights
    ├── MANAGEMENT-UIS.md   # Management interface guide
    └── COST-ANALYSIS.md    # Cost breakdown and optimization
```

## 🔧 Key Technologies

- **AWS Dedicated Hosts**: Single-tenant hardware for compliance
- **Kubernetes**: Container orchestration with custom scheduling
- **Terraform**: Infrastructure as Code
- **Calico**: Pod networking
- **Docker**: Container runtime

## 🎛️ Kubernetes Scheduling Features

- **Node Affinity**: Prefer dedicated hosts for compliance workloads
- **Taints & Tolerations**: Prevent unwanted pods on dedicated hardware
- **Priority Classes**: Higher priority for dedicated host workloads
- **Resource Limits**: Controlled resource allocation per pod

## 💰 Cost Analysis

**12-Month Total**: $100,172 USD ([AWS Calculator](https://calculator.aws/#/estimate?id=8083593f9ef4512e2de21dfc7df49fa8e598b914))
- **Per Dedicated Host**: $4,174/month ($50,086/year)
- **GP3 Storage**: $0.08/GB/month
- **Network Latency**: <5ms inter-AZ (published AWS latency)

See [COST-ANALYSIS.md](COST-ANALYSIS.md) for detailed breakdown and optimization strategies.

## 🧹 Cleanup

```bash
./scripts/cleanup.sh
```

This removes all Kubernetes resources and destroys the AWS infrastructure.

## 📚 Documentation

- [**Deployment Guide**](DEPLOYMENT-GUIDE.md) - Step-by-step deployment instructions
- [**Architecture Documentation**](ARCHITECTURE.md) - Technical deep dive
- [**Lessons Learned**](LESSONS-LEARNED.md) - Implementation challenges and solutions

## 🎯 Use Cases

This demo is perfect for organizations that need:

- **Regulatory Compliance**: Single-tenant hardware for sensitive workloads
- **Software Licensing**: Dedicated cores for licensed software
- **Performance Isolation**: Guaranteed resources without noisy neighbors
- **Cost Optimization**: Hybrid deployment model balancing compliance and cost

## 🤝 Contributing

Feel free to submit issues, fork the repository, and create pull requests for improvements.

## 📄 License

This project is open source and available under the MIT License.