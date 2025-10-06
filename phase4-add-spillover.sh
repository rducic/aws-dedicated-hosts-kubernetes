#!/bin/bash

# Phase 4: Add spillover instances (2 default tenancy workers)
set -e

echo "🌊 Phase 4: Add Spillover Capacity"
echo "=================================="
echo "Adding 2 default tenancy workers for spillover demonstration"

cd terraform

# Add default tenancy workers
terraform apply -var="dedicated_worker_count=96" -var="default_worker_count=2" -auto-approve

# Get master IP
MASTER_IP=$(terraform output -json master_info | jq -r '.public_ip')
echo "Master IP: $MASTER_IP"

echo "⏳ Waiting for spillover instances to initialize (2 minutes)..."
sleep 120

# Create script to join spillover workers
cat > /tmp/join_spillover_workers.sh << 'EOF'
#!/bin/bash
set -e

echo "🔗 Creating join token..."
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
echo "Join command: $JOIN_COMMAND"

# Get default worker IPs
DEFAULT_IPS="$1"

echo "🌐 Joining spillover workers..."
node_num=1
for ip in $DEFAULT_IPS; do
    echo "Joining k8s-default-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-default-$node_num" &
    node_num=$((node_num + 1))
done

echo "⏳ Waiting for spillover nodes to join..."
wait

echo "✅ Spillover workers joined!"
kubectl get nodes
EOF

# Get default worker IPs
DEFAULT_IPS=$(terraform output -json default_worker_private_ips | jq -r '.[]' | tr '\n' ' ')
scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no /tmp/join_spillover_workers.sh ec2-user@$MASTER_IP:/tmp/

# Execute join script
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "chmod +x /tmp/join_spillover_workers.sh && /tmp/join_spillover_workers.sh '$DEFAULT_IPS'"

echo "✅ Phase 4 complete!"
echo ""
echo "🎯 Final Infrastructure Summary:"
echo "================================"
kubectl get nodes --insecure-skip-tls-verify
echo ""
echo "📊 Node Distribution:"
echo "- Dedicated hosts: $(kubectl get nodes --insecure-skip-tls-verify | grep dedicated | wc -l) nodes"
echo "- Default tenancy: $(kubectl get nodes --insecure-skip-tls-verify | grep default | wc -l) nodes"
echo ""
echo "🚀 Ready for spillover demonstration!"
echo "Run: kubectl scale deployment cpu-load-app --replicas=100 -n demo --insecure-skip-tls-verify"

cd ..