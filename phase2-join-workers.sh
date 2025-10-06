#!/bin/bash

# Phase 2: Join the initial workers and set up cluster
set -e

echo "🔧 Phase 2: Join Workers and Setup Cluster"
echo "==========================================="

MASTER_IP=$(cd terraform && terraform output -json master_info | jq -r '.public_ip')
echo "Master IP: $MASTER_IP"

# Create join script for initial workers
cat > /tmp/join_initial_workers.sh << 'EOF'
#!/bin/bash
set -e

echo "🔗 Creating join token..."
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
echo "Join command: $JOIN_COMMAND"

# Get first 5 dedicated worker IPs
DEDICATED_IPS="$1"

echo "🏠 Joining initial 5 dedicated workers..."
node_num=1
for ip in $DEDICATED_IPS; do
    echo "Joining k8s-dedicated-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-dedicated-$node_num" &
    node_num=$((node_num + 1))
done

echo "⏳ Waiting for nodes to join..."
wait

echo "🏷️ Adding taints to dedicated nodes..."
for i in {1..5}; do
    kubectl taint node k8s-dedicated-$i dedicated-host=true:NoSchedule || true
done

echo "✅ Initial workers joined!"
kubectl get nodes
EOF

# Get worker IPs and copy script to master
DEDICATED_IPS=$(cd terraform && terraform output -json dedicated_worker_private_ips | jq -r '.[:5][]' | tr '\n' ' ')
scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no /tmp/join_initial_workers.sh ec2-user@$MASTER_IP:/tmp/

# Execute join script
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "chmod +x /tmp/join_initial_workers.sh && /tmp/join_initial_workers.sh '$DEDICATED_IPS'"

# Set up kubectl
echo "🔧 Setting up kubectl..."
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
sed -i '' "s/https:\/\/.*:6443/https:\/\/$MASTER_IP:6443/" ~/.kube/config

# Deploy initial workloads
echo "📦 Deploying demo workloads..."
kubectl create namespace demo --insecure-skip-tls-verify || true
kubectl apply -f k8s/metrics-server.yaml --insecure-skip-tls-verify
kubectl apply -f k8s/load-generator.yaml --insecure-skip-tls-verify

echo "✅ Phase 2 complete!"
echo "📊 Cluster Status:"
kubectl get nodes --insecure-skip-tls-verify
echo ""
echo "🔧 Next step: Run ./phase3-scale-to-100-percent.sh"