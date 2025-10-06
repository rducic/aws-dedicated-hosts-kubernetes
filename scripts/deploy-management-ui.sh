#!/bin/bash

set -e

echo "Deploying Kubernetes Management UIs..."

# Get master node IP
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

echo "Master node IP: $MASTER_IP"

# Copy manifests to master node
echo "Copying UI manifests..."
scp -o StrictHostKeyChecking=no k8s/dashboard.yaml ec2-user@$MASTER_IP:~/
scp -o StrictHostKeyChecking=no k8s/dashboard-admin.yaml ec2-user@$MASTER_IP:~/
scp -o StrictHostKeyChecking=no k8s/grafana.yaml ec2-user@$MASTER_IP:~/
scp -o StrictHostKeyChecking=no k8s/cluster-info.yaml ec2-user@$MASTER_IP:~/

# Deploy UIs
echo "Deploying Kubernetes Dashboard..."
ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP << 'EOF'
# Deploy Kubernetes Dashboard
kubectl apply -f dashboard.yaml
kubectl apply -f dashboard-admin.yaml

# Deploy Grafana
kubectl apply -f grafana.yaml

# Deploy Cluster Info Web Interface
kubectl apply -f cluster-info.yaml

echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard -n kubernetes-dashboard
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring
kubectl wait --for=condition=available --timeout=300s deployment/cluster-info-web -n demo

echo "Getting admin token for dashboard..."
kubectl -n kubernetes-dashboard create token admin-user --duration=24h

echo ""
echo "=== Management UIs Deployed ==="
echo ""
echo "Kubernetes Dashboard:"
echo "  URL: https://$MASTER_IP:30443"
echo "  Token: (see above)"
echo ""
echo "Grafana:"
echo "  URL: http://$MASTER_IP:30300"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Cluster Info Dashboard:"
echo "  URL: http://$MASTER_IP:30080"
echo ""
EOF

# Update security group to allow UI ports
echo "Updating security group for UI access..."
cd terraform
terraform apply -auto-approve
cd ..

echo ""
echo "=== Access Information ==="
echo ""
echo "Kubernetes Dashboard: https://$MASTER_IP:30443"
echo "Grafana: http://$MASTER_IP:30300"
echo "Cluster Info: http://$MASTER_IP:30080"
echo ""
echo "Note: For dashboard access, use the token displayed above"