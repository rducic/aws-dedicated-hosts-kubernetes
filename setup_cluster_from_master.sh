#!/bin/bash

# Setup cluster by running commands on the master node
set -e

MASTER_IP="54.70.94.249"

echo "🔧 Setting up Kubernetes cluster from master node"
echo "================================================="

# Create the join script on the master
cat > /tmp/join_all_workers.sh << 'EOF'
#!/bin/bash
set -e

echo "🔗 Creating new join token..."
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
echo "Join command: $JOIN_COMMAND"

# Get worker IPs from terraform outputs (we'll pass these as parameters)
DEDICATED_IPS="$1"
DEFAULT_IPS="$2"

echo "🏠 Joining dedicated host workers..."
node_num=1
for ip in $DEDICATED_IPS; do
    echo "Joining k8s-dedicated-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-dedicated-$node_num" &
    node_num=$((node_num + 1))
    
    # Limit concurrent joins to avoid overwhelming the master
    if [ $((node_num % 10)) -eq 0 ]; then
        echo "Waiting for batch to complete..."
        wait
    fi
done

echo "🌐 Joining default tenancy workers..."
node_num=1
for ip in $DEFAULT_IPS; do
    echo "Joining k8s-default-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-default-$node_num" &
    node_num=$((node_num + 1))
done

echo "⏳ Waiting for all joins to complete..."
wait

echo "🏷️ Adding taints to dedicated host nodes..."
for i in {1..96}; do
    kubectl taint node k8s-dedicated-$i dedicated-host=true:NoSchedule 2>/dev/null || true
done

echo "✅ All nodes joined successfully!"
kubectl get nodes
EOF

# Copy the script to master
echo "📤 Copying join script to master..."
scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no /tmp/join_all_workers.sh ec2-user@$MASTER_IP:/tmp/

# Get worker IPs
echo "📋 Getting worker node IPs..."
DEDICATED_IPS=$(cd terraform && terraform output -json dedicated_worker_private_ips | jq -r '.[]' | tr '\n' ' ')
DEFAULT_IPS=$(cd terraform && terraform output -json default_worker_private_ips | jq -r '.[]' | tr '\n' ' ')

# Execute the join script on master
echo "🚀 Executing cluster setup on master..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "chmod +x /tmp/join_all_workers.sh && /tmp/join_all_workers.sh '$DEDICATED_IPS' '$DEFAULT_IPS'"

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
echo "📊 Cluster Summary:"
kubectl get nodes -o wide --insecure-skip-tls-verify