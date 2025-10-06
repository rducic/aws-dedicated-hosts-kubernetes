#!/bin/bash

# Script to join a sample of worker nodes for testing
set -e

MASTER_IP="54.70.94.249"

echo "🔗 Getting join command from master..."
JOIN_COMMAND=$(ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo kubeadm token create --print-join-command")

echo "Join command: $JOIN_COMMAND"

# Get first 5 dedicated worker IPs and 2 default worker IPs
DEDICATED_IPS=$(cd terraform && terraform output -json dedicated_worker_private_ips | jq -r '.[:5][]')
DEFAULT_IPS=$(cd terraform && terraform output -json default_worker_private_ips | jq -r '.[]')

echo "🏠 Joining first 5 dedicated host workers from master..."
node_num=1
for ip in $DEDICATED_IPS; do
    echo "Joining k8s-dedicated-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip 'sudo $JOIN_COMMAND --node-name=k8s-dedicated-$node_num'" &
    
    node_num=$((node_num + 1))
done

echo "🌐 Joining default tenancy workers from master..."
node_num=1
for ip in $DEFAULT_IPS; do
    echo "Joining k8s-default-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip 'sudo $JOIN_COMMAND --node-name=k8s-default-$node_num'" &
    node_num=$((node_num + 1))
done

echo "⏳ Waiting for nodes to join..."
wait

echo "🏷️ Adding taints to dedicated host nodes..."
for i in {1..5}; do
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl taint node k8s-dedicated-$i dedicated-host=true:NoSchedule" || true
done

# Set up local kubectl access
echo "🔧 Setting up local kubectl access..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config

# Update server IP in kubeconfig
sed -i '' "s/https:\/\/.*:6443/https:\/\/$MASTER_IP:6443/" ~/.kube/config

# Test cluster
echo "🧪 Testing cluster connectivity..."
kubectl get nodes --insecure-skip-tls-verify

echo "✅ Sample cluster setup complete!"