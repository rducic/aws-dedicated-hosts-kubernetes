#!/bin/bash

# Quick setup with just a few nodes for demo
set -e

MASTER_IP="54.70.94.249"

echo "🚀 Quick cluster setup with sample nodes"
echo "========================================"

# Create a simple join script for just 3 dedicated + 2 default nodes
cat > /tmp/quick_join.sh << 'EOF'
#!/bin/bash
set -e

echo "🔗 Creating join token..."
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
echo "Join command: $JOIN_COMMAND"

# Join first 3 dedicated workers
echo "🏠 Joining 3 dedicated workers..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@10.0.10.225 "sudo $JOIN_COMMAND --node-name=k8s-dedicated-1" &
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@10.0.11.22 "sudo $JOIN_COMMAND --node-name=k8s-dedicated-2" &
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@10.0.10.198 "sudo $JOIN_COMMAND --node-name=k8s-dedicated-3" &

# Join 2 default workers
echo "🌐 Joining 2 default workers..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@10.0.10.14 "sudo $JOIN_COMMAND --node-name=k8s-default-1" &
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@10.0.11.241 "sudo $JOIN_COMMAND --node-name=k8s-default-2" &

echo "⏳ Waiting for nodes to join..."
wait

echo "🏷️ Adding taints to dedicated nodes..."
kubectl taint node k8s-dedicated-1 dedicated-host=true:NoSchedule || true
kubectl taint node k8s-dedicated-2 dedicated-host=true:NoSchedule || true
kubectl taint node k8s-dedicated-3 dedicated-host=true:NoSchedule || true

echo "✅ Quick setup complete!"
kubectl get nodes
EOF

# Copy and execute
scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no /tmp/quick_join.sh ec2-user@$MASTER_IP:/tmp/
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "chmod +x /tmp/quick_join.sh && /tmp/quick_join.sh"

# Set up kubectl
echo "🔧 Setting up kubectl..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
sed -i '' "s/https:\/\/.*:6443/https:\/\/$MASTER_IP:6443/" ~/.kube/config

echo "🧪 Testing cluster..."
kubectl get nodes --insecure-skip-tls-verify

echo "✅ Quick cluster ready for demo!"