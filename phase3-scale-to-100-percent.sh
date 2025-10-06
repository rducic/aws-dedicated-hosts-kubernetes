#!/bin/bash

# Phase 3: Scale to 100% dedicated host utilization (96 instances)
set -e

echo "📈 Phase 3: Scale to 100% Dedicated Host Utilization"
echo "===================================================="
echo "Scaling from 5 to 96 dedicated host workers"

cd terraform

# Scale up to 96 dedicated workers
terraform apply -var="dedicated_worker_count=96" -var="default_worker_count=0" -auto-approve

# Get master IP
MASTER_IP=$(terraform output -json master_info | jq -r '.public_ip')
echo "Master IP: $MASTER_IP"

echo "⏳ Waiting for new instances to initialize (3 minutes)..."
sleep 180

# Create script to join all remaining workers
cat > /tmp/join_remaining_workers.sh << 'EOF'
#!/bin/bash
set -e

echo "🔗 Creating join token..."
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
echo "Join command: $JOIN_COMMAND"

# Get all dedicated worker IPs (skip first 5 already joined)
REMAINING_IPS="$1"

echo "🏠 Joining remaining dedicated workers (6-96)..."
node_num=6
for ip in $REMAINING_IPS; do
    echo "Joining k8s-dedicated-$node_num ($ip)..."
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$ip "sudo $JOIN_COMMAND --node-name=k8s-dedicated-$node_num" &
    node_num=$((node_num + 1))
    
    # Join in batches of 10 to avoid overwhelming the master
    if [ $((node_num % 10)) -eq 0 ]; then
        echo "Waiting for batch to complete..."
        wait
    fi
done

echo "⏳ Waiting for final batch..."
wait

echo "🏷️ Adding taints to new dedicated nodes..."
for i in {6..96}; do
    kubectl taint node k8s-dedicated-$i dedicated-host=true:NoSchedule 2>/dev/null || true
done

echo "✅ All dedicated workers joined!"
kubectl get nodes | grep dedicated | wc -l
EOF

# Get remaining worker IPs (skip first 5)
REMAINING_IPS=$(terraform output -json dedicated_worker_private_ips | jq -r '.[5:][]' | tr '\n' ' ')
scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no /tmp/join_remaining_workers.sh ec2-user@$MASTER_IP:/tmp/

# Execute join script
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "chmod +x /tmp/join_remaining_workers.sh && /tmp/join_remaining_workers.sh '$REMAINING_IPS'"

echo "✅ Phase 3 complete!"
echo "📊 Dedicated Hosts at 100% Utilization:"
kubectl get nodes --insecure-skip-tls-verify | grep dedicated | wc -l
echo ""
echo "🔧 Next step: Run ./phase4-add-spillover.sh"

cd ..