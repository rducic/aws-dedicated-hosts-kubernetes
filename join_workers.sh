#!/bin/bash

# Script to join worker nodes from the master
set -e

MASTER_IP="54.70.94.249"

echo "🔗 Getting join command from master..."
JOIN_COMMAND=$(ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo kubeadm token create --print-join-command")

echo "Join command: $JOIN_COMMAND"

# Get worker IPs
DEDICATED_IPS=$(cd terraform && terraform output -json dedicated_worker_private_ips | jq -r '.[]')
DEFAULT_IPS=$(cd terraform && terraform output -json default_worker_private_ips | jq -r '.[]')

echo "🏠 Joining dedicated host workers from master..."
node_num=1
for ip in $DEDICATED_IPS; do
    echo "Joining k8s-dedicated-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "ssh -o StrictHostKeyChecking=no ec2-user@$ip 'sudo $JOIN_COMMAND --node-name=k8s-dedicated-$node_num'"
    
    # Add taint for dedicated hosts
    sleep 5
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl taint node k8s-dedicated-$node_num dedicated-host=true:NoSchedule"
    
    node_num=$((node_num + 1))
done

echo "🌐 Joining default tenancy workers from master..."
node_num=1
for ip in $DEFAULT_IPS; do
    echo "Joining k8s-default-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "ssh -o StrictHostKeyChecking=no ec2-user@$ip 'sudo $JOIN_COMMAND --node-name=k8s-default-$node_num'"
    node_num=$((node_num + 1))
done

# Set up local kubectl access
echo "🔧 Setting up local kubectl access..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config

# Update server IP in kubeconfig
sed -i '' "s/https:\/\/.*:6443/https:\/\/$MASTER_IP:6443/" ~/.kube/config

# Test cluster
echo "🧪 Testing cluster connectivity..."
kubectl get nodes --insecure-skip-tls-verify

echo "✅ Cluster setup complete!"