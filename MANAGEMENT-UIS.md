# Management UIs for AWS Dedicated Hosts Kubernetes Demo

## 🎛️ Deployed Management Interfaces

### 1. Kubernetes Dashboard ✅ **ACCESSIBLE**
- **URL**: `https://<MASTER_PUBLIC_IP>:30443`
- **Purpose**: Full-featured Kubernetes cluster management interface
- **Authentication**: Token-based (generate new token as needed)
- **Features**:
  - View and manage all Kubernetes resources
  - Monitor cluster health and metrics
  - Deploy and scale applications
  - View logs and events

**Get Master Public IP**:
```bash
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')
echo "Master IP: $MASTER_IP"
```

**Generate Access Token**:
```bash
ssh ec2-user@$MASTER_IP "kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
```

### 2. Grafana Monitoring Dashboard ✅ **ACCESSIBLE**
- **URL**: `http://<MASTER_PUBLIC_IP>:30300`
- **Username**: `admin`
- **Password**: `admin123`
- **Purpose**: Metrics visualization and monitoring
- **Features**:
  - Create custom dashboards
  - Monitor cluster and application metrics
  - Set up alerts and notifications
  - Historical data analysis

### 3. Cluster Info Web Interface ✅ **ACCESSIBLE**
- **URL**: `http://<MASTER_PUBLIC_IP>:30080`
- **Purpose**: Demo-specific information and architecture overview
- **Features**:
  - Visual architecture diagram
  - Scheduling behavior explanation
  - Quick access to management links
  - Test commands and examples

## 🔧 Port Configuration

The following NodePort services are configured and **security group rules have been added**:

| Service | Port | Protocol | Purpose | Status |
|---------|------|----------|---------|--------|
| Kubernetes Dashboard | 30443 | HTTPS | Cluster management | ✅ Accessible |
| Grafana | 30300 | HTTP | Monitoring dashboard | ✅ Accessible |
| Cluster Info | 30080 | HTTP | Demo information | ✅ Accessible |

**Security Group ID**: `sg-007aacb1475311353`

### Automated Security Group Update
Use the provided script to update security groups for future deployments:
```bash
./scripts/update-security-group.sh
```

## 🚀 Quick Access Commands

### Generate New Dashboard Token
```bash
# SSH to master node
ssh ec2-user@35.91.75.188

# Generate new 24-hour token
kubectl -n kubernetes-dashboard create token admin-user --duration=24h
```

### Check Service Status
```bash
# View all management services
kubectl get svc -A | grep -E "(dashboard|grafana|cluster-info)"

# Check pod status
kubectl get pods -A | grep -E "(dashboard|grafana|cluster-info)"
```

### Port Forwarding (Alternative Access)
If NodePort access is blocked, you can use port forwarding:

```bash
# Kubernetes Dashboard
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443

# Grafana
kubectl port-forward -n monitoring service/grafana 3000:3000

# Cluster Info
kubectl port-forward -n demo service/cluster-info-web 8080:80
```

## 📊 What You Can Do

### Kubernetes Dashboard
1. **Navigate to Workloads** → **Deployments** to see demo applications
2. **View Nodes** to see dedicated vs default tenancy nodes
3. **Check Events** to see scheduling decisions
4. **Scale Deployments** to test overflow behavior
5. **View Resource Usage** across nodes

### Grafana
1. **Import Kubernetes dashboards** from Grafana community
2. **Create custom dashboards** for dedicated host metrics
3. **Set up alerts** for resource utilization
4. **Monitor pod distribution** across node types

### Cluster Info Dashboard
1. **Understand the architecture** with visual diagrams
2. **Learn about scheduling behavior** and priorities
3. **Access quick links** to other management tools
4. **Copy test commands** for experimentation

## 🔒 Security Considerations

### Production Recommendations
1. **Restrict Access**: Use VPN or bastion hosts instead of public access
2. **Enable HTTPS**: Configure TLS for all web interfaces
3. **RBAC**: Implement proper role-based access control
4. **Authentication**: Integrate with corporate identity providers
5. **Network Policies**: Restrict pod-to-pod communication

### Current Demo Security
- ⚠️ **Public Access**: All UIs are accessible from the internet
- ⚠️ **Default Credentials**: Grafana uses default admin credentials
- ⚠️ **Cluster Admin**: Dashboard token has full cluster access
- ✅ **HTTPS**: Dashboard uses HTTPS with self-signed certificates

## 🛠️ Troubleshooting

### Dashboard Access Issues
```bash
# Check if dashboard pod is running
kubectl get pods -n kubernetes-dashboard

# View dashboard logs
kubectl logs -n kubernetes-dashboard deployment/kubernetes-dashboard

# Regenerate token if expired
kubectl -n kubernetes-dashboard create token admin-user --duration=24h
```

### Grafana Access Issues
```bash
# Check Grafana pod status
kubectl get pods -n monitoring

# View Grafana logs
kubectl logs -n monitoring deployment/grafana

# Reset admin password
kubectl exec -n monitoring deployment/grafana -- grafana-cli admin reset-admin-password newpassword
```

### Network Connectivity Issues
```bash
# Check NodePort services
kubectl get svc -A --field-selector spec.type=NodePort

# Test internal connectivity
kubectl exec -it <any-pod> -- curl http://grafana.monitoring:3000

# Check security group rules (if you have AWS CLI access)
aws ec2 describe-security-groups --group-ids <security-group-id>
```

## 📈 Monitoring Dedicated Hosts

### Key Metrics to Watch
1. **Host Utilization**: CPU, memory, network usage per dedicated host
2. **Pod Distribution**: Number of pods per node type
3. **Scheduling Latency**: Time to schedule pods on dedicated vs default nodes
4. **Resource Efficiency**: Utilization rates across different tenancy types

### Grafana Dashboard Ideas
1. **Dedicated Host Overview**: Resource usage, pod count, scheduling metrics
2. **Cost Analysis**: Utilization rates, cost per workload
3. **Compliance Tracking**: Which workloads are on dedicated hardware
4. **Performance Comparison**: Dedicated vs default tenancy performance

## 🎯 Next Steps

1. **Explore the Dashboards**: Navigate through each interface to understand the cluster
2. **Test Scaling**: Use the dashboard to scale deployments and observe behavior
3. **Create Custom Views**: Set up Grafana dashboards for your specific needs
4. **Monitor Costs**: Track dedicated host utilization and cost efficiency
5. **Plan Production**: Use insights to design your production architecture