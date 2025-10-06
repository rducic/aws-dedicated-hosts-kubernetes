# Lessons Learned - AWS Dedicated Hosts with Kubernetes Demo

## Deployment Challenges and Solutions

### 1. Kubernetes Repository Issues

**Problem**: The original Kubernetes package repository (`packages.cloud.google.com`) was deprecated, causing installation failures.

**Error**:
```bash
sudo: kubeadm: command not found
```

**Solution**: Updated to the new official Kubernetes repository:
```bash
# Old (deprecated)
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64

# New (current)
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
```

**Lesson**: Always use the latest official package repositories and check for deprecation notices.

### 2. Invalid Hostname Configuration

**Problem**: EC2 user-data script generated invalid hostnames with trailing dashes or dots from IP addresses.

**Error**:
```bash
nodeRegistration.name: Invalid value: "k8s-dedicated-": a lowercase RFC 1123 subdomain must consist of lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character
```

**Root Cause**: IP address replacement logic created malformed hostnames:
```bash
# This created hostnames like "k8s-dedicated-10.0.1.137" (invalid)
hostnamectl set-hostname k8s-dedicated-$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
```

**Solution**: 
1. Replace dots with dashes in IP addresses
2. Use proper variable expansion
3. Manually set simple hostnames for demo

```bash
# Fixed approach
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 | tr '.' '-')
hostnamectl set-hostname k8s-dedicated-$PRIVATE_IP
```

**Lesson**: Always validate hostname formats and test user-data scripts thoroughly.

### 3. Security Group Configuration

**Problem**: Kubernetes API server (port 6443) was only accessible from within the VPC, preventing external kubectl access.

**Error**:
```bash
dial tcp 10.0.1.137:6443: i/o timeout
```

**Root Cause**: Security group rule restricted API access:
```hcl
# Too restrictive for demo
ingress {
  from_port   = 6443
  to_port     = 6443
  protocol    = "tcp"
  cidr_blocks = [aws_vpc.main.cidr_block]  # Only VPC access
}
```

**Solution**: 
1. Allow external access for demo purposes
2. Use SSH tunneling as alternative
3. Update kubeconfig to use public IP

**Lesson**: Consider network access patterns when designing security groups. For production, use bastion hosts or VPN access.

### 4. Kubelet Configuration Issues

**Problem**: Node labels and taints defined in user-data didn't apply correctly.

**Root Cause**: Kubelet configuration file path and timing issues during bootstrap.

**Solution**: Manual configuration after cluster initialization:
```bash
# Add labels manually
kubectl label node k8s-master tenancy=dedicated node-type=dedicated-host

# Add taints manually  
kubectl taint node k8s-master dedicated-host=true:NoSchedule
```

**Lesson**: For complex kubelet configurations, consider using kubeadm configuration files or post-deployment automation.

### 5. Terraform Template Variables

**Problem**: User-data scripts used undefined template variables causing Terraform errors.

**Error**:
```bash
vars map does not contain key "PRIVATE_IP", referenced at ./user-data-dedicated.sh:40,42-52
```

**Root Cause**: Mixed shell variables with Terraform template syntax.

**Solution**: Use shell variables instead of Terraform template variables in user-data scripts.

**Lesson**: Keep user-data scripts self-contained and avoid mixing template engines.

## Kubernetes Scheduling Insights

### 1. Pod Placement Behavior

**Observation**: Pods with node affinity preferences don't guarantee placement on preferred nodes when resources are available.

**Actual Behavior**:
- Some "dedicated tier" pods scheduled on default tenancy nodes
- Kubernetes scheduler balances multiple factors beyond affinity

**Explanation**: The scheduler considers:
- Resource availability
- Node load balancing
- Pod anti-affinity rules
- Quality of Service classes

**Lesson**: Use `requiredDuringSchedulingIgnoredDuringExecution` for strict placement requirements, `preferredDuringSchedulingIgnoredDuringExecution` for soft preferences.

### 2. Taint and Toleration Effectiveness

**Success**: Taints effectively prevented unwanted pods from scheduling on dedicated hosts.

**Key Learning**: Taints are more effective than node affinity for ensuring dedicated resource usage.

**Best Practice**:
```yaml
# Effective combination
tolerations:
- key: "dedicated-host"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:  # Use required for strict placement
      nodeSelectorTerms:
      - matchExpressions:
        - key: tenancy
          operator: In
          values: ["dedicated"]
```

### 3. Priority Classes Impact

**Observation**: Priority classes worked as expected for pod scheduling order but didn't override resource constraints.

**Lesson**: Priority affects scheduling order and preemption, not resource allocation limits.

## Infrastructure Design Insights

### 1. Dedicated Host Utilization

**Finding**: Single m5.large instances on dedicated hosts significantly underutilize the hardware.

**Metrics**:
- Host Capacity: Full m5.large family capacity
- Actual Usage: 1 instance per host
- Utilization: ~10-20% of available capacity

**Optimization Opportunities**:
1. Deploy multiple smaller instances per host
2. Use larger instance types to better utilize host capacity
3. Implement bin-packing algorithms for optimal placement

### 2. Multi-AZ Deployment Benefits

**Success**: Multi-AZ deployment provided resilience and demonstrated real-world architecture patterns.

**Benefits Observed**:
- Automatic pod rescheduling during simulated failures
- Network latency remained acceptable (<5ms inter-AZ)
- Load distribution across availability zones

### 3. Network Performance

**Findings**:
- Calico networking performed well with default configuration
- Pod-to-pod communication was seamless across AZs
- No significant network bottlenecks observed

## Operational Insights

### 1. Monitoring and Observability

**Gap**: Limited monitoring in the demo setup.

**Recommendations for Production**:
```bash
# Essential monitoring components
- Prometheus + Grafana for metrics
- ELK stack for logging  
- AWS CloudWatch for infrastructure metrics
- Kubernetes Dashboard for cluster visibility
```

### 2. Backup and Recovery

**Missing**: No backup strategy implemented in demo.

**Production Requirements**:
- Regular etcd backups
- Persistent volume snapshots
- Configuration backup (Terraform state, K8s manifests)
- Disaster recovery procedures

### 3. Security Hardening

**Demo Shortcuts Taken**:
- Open security groups (SSH from anywhere)
- No RBAC configuration
- No network policies
- No secrets management

**Production Hardening Needed**:
- Restrict security group access
- Implement RBAC
- Use AWS IAM roles for service accounts
- Deploy network policies
- Integrate with AWS Secrets Manager

## Cost Optimization Learnings

### 1. Dedicated Host Economics

**Reality Check**:
- Dedicated hosts are expensive (~$1,000-2,000/month each)
- Underutilization significantly increases per-workload cost
- ROI depends heavily on utilization rates

**Optimization Strategies**:
1. Maximize instance density per host
2. Use Reserved Instances for predictable workloads
3. Implement automated scaling to optimize utilization
4. Consider Savings Plans for flexible commitment

### 2. Default Tenancy Cost Efficiency

**Finding**: Default tenancy instances provide excellent cost/performance ratio for overflow capacity.

**Strategy**: Use dedicated hosts for compliance-required workloads, default tenancy for everything else.

## Automation and CI/CD Insights

### 1. Infrastructure as Code Benefits

**Success**: Terraform provided repeatable, version-controlled infrastructure deployment.

**Improvements Needed**:
- Better state management (remote backend)
- Module organization for reusability
- Automated testing of infrastructure changes

### 2. Configuration Management

**Challenge**: Manual post-deployment configuration steps.

**Solution Approaches**:
- Ansible playbooks for configuration management
- Kubernetes operators for automated cluster management
- GitOps workflows for application deployment

## Recommendations for Production

### 1. Architecture Improvements

```yaml
Production Architecture:
├── Multi-region deployment for DR
├── Private subnets with NAT gateways
├── Application Load Balancer for ingress
├── Auto Scaling Groups for worker nodes
├── Managed services where possible (RDS, ElastiCache)
└── Comprehensive monitoring and alerting
```

### 2. Security Enhancements

- Implement AWS IAM roles for service accounts
- Use AWS Systems Manager for secure access
- Deploy Falco for runtime security monitoring
- Implement Pod Security Standards
- Regular security scanning and updates

### 3. Operational Excellence

- Implement comprehensive logging and monitoring
- Establish backup and disaster recovery procedures
- Create runbooks for common operational tasks
- Implement automated scaling and self-healing
- Regular chaos engineering exercises

### 4. Cost Management

- Implement resource quotas and limits
- Use cluster autoscaling for dynamic capacity
- Regular cost reviews and optimization
- Implement chargeback/showback for teams
- Consider spot instances for non-critical workloads

## Key Takeaways

1. **Plan for Complexity**: Kubernetes on dedicated hosts adds operational complexity that must be carefully managed.

2. **Test Thoroughly**: User-data scripts, networking, and security configurations need extensive testing.

3. **Monitor Everything**: Comprehensive monitoring is essential for troubleshooting and optimization.

4. **Automate Wisely**: Balance automation with operational simplicity, especially for complex configurations.

5. **Cost Awareness**: Dedicated hosts require careful capacity planning to achieve cost efficiency.

6. **Security First**: Implement security best practices from the beginning rather than retrofitting.

7. **Documentation Matters**: Comprehensive documentation is crucial for operational success and knowledge transfer.