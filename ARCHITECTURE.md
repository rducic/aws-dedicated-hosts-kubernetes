# AWS Dedicated Hosts with Kubernetes - Architecture Documentation

## System Architecture

### High-Level Design

This solution demonstrates a hybrid cloud architecture where workloads intelligently distribute across dedicated and shared infrastructure based on capacity and scheduling preferences.

```
┌───────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                  │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                        VPC (10.0.0.0/16)                           │   │
│  │                                                                    │   │
│  │  ┌──────────────────────┐    ┌──────────────────────────────────┐  │   │
│  │  │    Subnet AZ-A       │    │         Subnet AZ-B              │  │   │
│  │  │   (10.0.1.0/24)      │    │        (10.0.2.0/24)             │  │   │
│  │  │                      │    │                                  │  │   │
│  │  │  ┌─────────────────┐ │    │  ┌─────────────────────────────┐ │  │   │
│  │  │  │ Dedicated Host  │ │    │  │      Dedicated Host         │ │  │   │
│  │  │  │   h-xxxxxxx     │ │    │  │        h-yyyyyyy            │ │  │   │
│  │  │  │                 │ │    │  │                             │ │  │   │
│  │  │  │ ┌─────────────┐ │ │    │  │ ┌─────────────────────────┐ │ │  │   │
│  │  │  │ │k8s-master   │ │ │    │  │ │   k8s-dedicated-2       │ │ │  │   │
│  │  │  │ │Control Plane│ │ │    │  │ │   Worker Node           │ │ │  │   │
│  │  │  │ │Tainted      │ │ │    │  │ │   Tainted               │ │ │  │   │
│  │  │  │ └─────────────┘ │ │    │  │ └─────────────────────────┘ │ │  │   │
│  │  │  └─────────────────┘ │    │  └─────────────────────────────┘ │  │   │
│  │  │                      │    │                                  │  │   │
│  │  │  ┌─────────────────┐ │    │  ┌─────────────────────────────┐ │  │   │
│  │  │  │ Default Tenancy │ │    │  │      Default Tenancy        │ │  │   │
│  │  │  │                 │ │    │  │                             │ │  │   │
│  │  │  │ ┌─────────────┐ │ │    │  │ ┌─────────────────────────┐ │ │  │   │
│  │  │  │ │k8s-default-1│ │ │    │  │ │   k8s-default-2         │ │ │  │   │
│  │  │  │ │Worker Node  │ │ │    │  │ │   Worker Node           │ │ │  │   │
│  │  │  │ │No Taints    │ │ │    │  │ │   No Taints             │ │ │  │   │
│  │  │  │ └─────────────┘ │ │    │  │ └─────────────────────────┘ │ │  │   │
│  │  │  └─────────────────┘ │    │  └─────────────────────────────┘ │  │   │
│  │  └──────────────────────┘    └──────────────────────────────────┘  │   │
│  └────────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Infrastructure Layer

#### AWS Dedicated Hosts
- **Purpose**: Provide single-tenant hardware for compliance/licensing requirements
- **Configuration**: 2 hosts across 2 AZs for high availability
- **Instance Type**: m5.large (2 vCPU, 8 GB RAM)
- **Capacity**: Each host can run multiple instances up to its resource limits

#### EC2 Instances
- **Dedicated Host Instances**: 2 instances (1 per host)
- **Default Tenancy Instances**: 2 instances for overflow capacity
- **Operating System**: Amazon Linux 2
- **Networking**: Public IPs for demo access, private IPs for cluster communication

#### Networking
```
VPC: 10.0.0.0/16
├── Subnet AZ-A: 10.0.1.0/24
├── Subnet AZ-B: 10.0.2.0/24
├── Internet Gateway: igw-xxxxxxx
└── Route Table: Public routes to IGW
```

### 2. Kubernetes Layer

#### Cluster Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                      │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                 │
│  │   Control Plane │  │   Worker Nodes  │                 │
│  │                 │  │                 │                 │
│  │  ┌───────────┐  │  │  ┌───────────┐  │                 │
│  │  │kube-api   │  │  │  │kubelet    │  │                 │
│  │  │etcd       │  │  │  │kube-proxy │  │                 │
│  │  │scheduler  │  │  │  │container  │  │                 │
│  │  │controller │  │  │  │runtime    │  │                 │
│  │  └───────────┘  │  │  └───────────┘  │                 │
│  └─────────────────┘  └─────────────────┘                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Pod Network (Calico)                   │   │
│  │                192.168.0.0/16                       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

#### Node Configuration

| Node | Type | Tenancy | Labels | Taints |
|------|------|---------|--------|--------|
| k8s-master | Control Plane | Dedicated | tenancy=dedicated, node-type=dedicated-host | dedicated-host=true:NoSchedule, node-role.kubernetes.io/control-plane:NoSchedule |
| k8s-dedicated-2 | Worker | Dedicated | tenancy=dedicated, node-type=dedicated-host | dedicated-host=true:NoSchedule |
| k8s-default-1 | Worker | Default | tenancy=default, node-type=default-tenancy | None |
| k8s-default-2 | Worker | Default | tenancy=default, node-type=default-tenancy | None |

### 3. Application Layer

#### Workload Types

**Dedicated Tier Workloads**
```yaml
spec:
  priorityClassName: dedicated-host-priority  # Priority: 1000
  tolerations:
  - key: "dedicated-host"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
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

**Overflow Tier Workloads**
```yaml
spec:
  priorityClassName: default-tenancy-priority  # Priority: 100
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: tenancy
            operator: In
            values: ["default"]
```

## Scheduling Logic

### Pod Placement Algorithm

```
1. Pod Creation Request
   ↓
2. Priority Class Evaluation
   ↓
3. Node Affinity Check
   ↓
4. Taint/Toleration Validation
   ↓
5. Resource Availability Check
   ↓
6. Placement Decision

Decision Tree:
├── High Priority Pod (dedicated-host-priority)
│   ├── Has dedicated-host toleration?
│   │   ├── Yes → Try dedicated hosts first
│   │   │   ├── Capacity available? → Schedule on dedicated
│   │   │   └── No capacity? → Schedule on default (overflow)
│   │   └── No → Schedule on default tenancy only
│   └── 
└── Low Priority Pod (default-tenancy-priority)
    └── Schedule on default tenancy nodes
```

### Capacity Management

**Dedicated Host Capacity**
- Physical: 2 vCPU, 8 GB RAM per host
- Kubernetes: ~1.5 vCPU, ~6 GB RAM available (after system overhead)
- Pod Limit: ~6-8 pods per host (depending on resource requests)

**Overflow Behavior**
1. Dedicated hosts fill first (preferred scheduling)
2. When capacity reached, pods overflow to default tenancy
3. Higher priority pods can preempt lower priority pods if needed

## Security Architecture

### Network Security

```
Security Group Rules:
┌─────────────────────────────────────────────────────────┐
│ Ingress Rules                                           │
├─────────────────────────────────────────────────────────┤
│ SSH (22)           │ 0.0.0.0/0        │ Management      │
│ K8s API (6443)     │ 0.0.0.0/0        │ Cluster Access  │
│ Kubelet (10250)    │ Self-reference   │ Node Comm       │
│ Pod Network (All)  │ Self-reference   │ Pod-to-Pod      │
└─────────────────────────────────────────────────────────┘
```

### Kubernetes RBAC

```
Default Service Accounts:
├── system:masters (cluster-admin)
├── system:nodes (node access)
├── system:serviceaccounts:kube-system
└── system:serviceaccounts:demo
```

## Data Flow

### Pod Scheduling Flow

```
kubectl apply → API Server → Scheduler → Kubelet → Container Runtime
     ↓              ↓           ↓          ↓            ↓
  Manifest    Validation   Placement   Pod Start   Image Pull
   Parsing     & Storage   Decision    & Monitor   & Execute
```

### Network Traffic Flow

```
External → Load Balancer → Service → Pod
   ↓            ↓           ↓        ↓
Internet    AWS ALB      ClusterIP  Container
Traffic     (Future)     (Current)   Application
```

## Monitoring and Observability

### Metrics Collection Points

1. **Infrastructure Metrics**
   - EC2 instance utilization
   - Dedicated host capacity
   - Network throughput

2. **Kubernetes Metrics**
   - Pod scheduling latency
   - Node resource utilization
   - Cluster events

3. **Application Metrics**
   - Pod distribution
   - Scheduling decisions
   - Resource consumption

### Logging Architecture

```
Application Logs → Container Runtime → Kubelet → Log Aggregation
      ↓                    ↓             ↓            ↓
   stdout/stderr        Docker Logs   Node Logs   CloudWatch
                                                  (Future)
```

## Scalability Considerations

### Horizontal Scaling

**Current Limits**
- Dedicated Hosts: 2 (can scale to hundreds)
- Worker Nodes: 4 (can scale to thousands)
- Pods per Node: ~110 (Kubernetes default)

**Scaling Strategies**
1. Add more dedicated hosts for predictable workloads
2. Add default tenancy instances for overflow capacity
3. Implement cluster autoscaling for dynamic scaling

### Vertical Scaling

**Instance Types**
- Current: m5.large (2 vCPU, 8 GB)
- Options: m5.xlarge, m5.2xlarge, etc.
- Considerations: Dedicated host family compatibility

## Disaster Recovery

### Backup Strategy

1. **etcd Backups**: Regular snapshots of cluster state
2. **Configuration Backups**: Terraform state, Kubernetes manifests
3. **Application Data**: Persistent volume snapshots

### Recovery Procedures

1. **Node Failure**: Kubernetes automatically reschedules pods
2. **AZ Failure**: Multi-AZ deployment provides resilience
3. **Cluster Failure**: Restore from etcd backup and redeploy

## Performance Characteristics

### Latency Metrics

- Pod startup time: ~30-60 seconds
- Scheduling latency: <1 second
- Network latency: <1ms intra-AZ, <5ms inter-AZ

### Throughput Metrics

- API requests: ~1000 QPS per master
- Pod scheduling: ~100 pods/minute
- Network throughput: Up to 10 Gbps per instance

## Cost Optimization


### Optimization Strategies

1. **Right-sizing**: Match instance types to workload requirements
2. **Scheduling Efficiency**: Maximize dedicated host utilization
3. **Reserved Instances**: Use RIs for predictable workloads
4. **Spot Instances**: Consider for non-critical overflow capacity