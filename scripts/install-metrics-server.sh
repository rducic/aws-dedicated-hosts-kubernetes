#!/bin/bash

set -e

echo "Installing Kubernetes Metrics Server..."

# Get master node IP
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

echo "Master node IP: $MASTER_IP"

# Copy metrics server manifest to master node
echo "Copying metrics server manifest..."
scp -o StrictHostKeyChecking=no k8s/metrics-server.yaml ec2-user@$MASTER_IP:~/

# Install metrics server
echo "Installing metrics server..."
ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP << 'EOF'
kubectl apply -f metrics-server.yaml

echo "Waiting for metrics server to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system

echo "Metrics server installation complete!"

# Test metrics API
echo "Testing metrics API..."
sleep 10
kubectl top nodes
EOF

echo "Metrics server installed successfully!"