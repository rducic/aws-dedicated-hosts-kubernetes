#!/bin/bash

# Set up the Kubernetes cluster and join worker nodes
set -e

echo "🔧 Setting up Kubernetes Cluster"
echo "================================"

cd terraform

# Get infrastructure details
MASTER_IP=$(terraform output -json master_info | jq -r '.public_ip')
DEDICATED_IPS=$(terraform output -json dedicated_worker_private_ips | jq -r '.[]')
DEFAULT_IPS=$(terraform output -json default_worker_private_ips | jq -r '.[]')

echo "📋 Cluster nodes:"
echo "Master: $MASTER_IP"
echo "Dedicated workers: $DEDICATED_IPS"
echo "Default workers: $DEFAULT_IPS"
echo ""

# Wait for master to be ready
echo "⏳ Waiting for master node to be ready..."
for i in {1..30}; do
    if ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl get nodes" &>/dev/null; then
        echo "✅ Master node is ready!"
        break
    fi
    echo "Waiting for master... attempt $i/30"
    sleep 30
done

# Get join command
echo "🔗 Getting cluster join command..."
JOIN_COMMAND=$(ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo kubeadm token create --print-join-command")

echo "Join command: $JOIN_COMMAND"
echo ""

# Join dedicated workers (using master as jump host)
echo "🏠 Joining dedicated host workers..."
node_num=1
for ip in $DEDICATED_IPS; do
    echo "Joining k8s-dedicated-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -W %h:%p ec2-user@$MASTER_IP" ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-dedicated-$node_num"
    
    # Add taint for dedicated hosts
    sleep 10
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl taint node k8s-dedicated-$node_num dedicated-host=true:NoSchedule"
    
    node_num=$((node_num + 1))
done

# Join default workers (using master as jump host)
echo "🌐 Joining default tenancy workers..."
node_num=1
for ip in $DEFAULT_IPS; do
    echo "Joining k8s-default-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -W %h:%p ec2-user@$MASTER_IP" ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-default-$node_num"
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

echo ""
echo "✅ Cluster setup complete!"
echo ""
echo "🎯 Cluster Summary:"
kubectl get nodes -o wide --insecure-skip-tls-verify
echo ""
echo "🔧 Next steps:"
echo "1. Run: ./scripts/03-deploy-workloads.sh"
echo "2. Run: ./scripts/04-generate-load.sh"

cd ..