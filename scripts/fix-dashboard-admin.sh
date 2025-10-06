#!/bin/bash

set -e

echo "🔧 Fixing Kubernetes Dashboard Admin User"
echo "========================================="

# Get master node IP
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

echo "Master node IP: $MASTER_IP"

# Copy admin user manifest to master node
echo "📋 Copying admin user manifest..."
scp -o StrictHostKeyChecking=no k8s/dashboard-admin-user.yaml ec2-user@$MASTER_IP:~/

# Deploy admin user
echo "👤 Creating admin user..."
ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl apply -f dashboard-admin-user.yaml"

# Generate token
echo "🔑 Generating access token..."
TOKEN=$(ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl -n kubernetes-dashboard create token admin-user --duration=24h")

echo ""
echo "✅ Dashboard Admin User Fixed!"
echo ""
echo "🎛️  Kubernetes Dashboard Access:"
echo "   URL: https://$MASTER_IP:30443"
echo "   Token: $TOKEN"
echo ""
echo "📋 Copy the token above to access the dashboard"
echo ""
echo "🔄 To generate a new token later:"
echo "   ssh ec2-user@$MASTER_IP"
echo "   kubectl -n kubernetes-dashboard create token admin-user --duration=24h"