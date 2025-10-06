#!/bin/bash

set -e

echo "Setting up Kubernetes cluster with dedicated hosts..."

# Get Terraform outputs
DEDICATED_IPS=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[]')
DEFAULT_IPS=$(terraform -chdir=terraform output -json default_node_ips | jq -r '.[]')
CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name)

# Convert to arrays
DEDICATED_ARRAY=($DEDICATED_IPS)
DEFAULT_ARRAY=($DEFAULT_IPS)

MASTER_IP=${DEDICATED_ARRAY[0]}

echo "Master node IP: $MASTER_IP"
echo "Dedicated nodes: ${DEDICATED_ARRAY[@]}"
echo "Default nodes: ${DEFAULT_ARRAY[@]}"

# Initialize cluster on first dedicated host
echo "Initializing cluster on master node..."
ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP << EOF
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Set up kubectl for ec2-user
mkdir -p /home/ec2-user/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
sudo chown ec2-user:ec2-user /home/ec2-user/.kube/config

# Install Calico network plugin
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Get join command
kubeadm token create --print-join-command > /tmp/join-command.sh
EOF

# Copy kubeconfig locally
echo "Copying kubeconfig..."
scp -o StrictHostKeyChecking=no ec2-user@$MASTER_IP:/home/ec2-user/.kube/config ~/.kube/config-$CLUSTER_NAME

# Get join command
JOIN_CMD=$(ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "cat /tmp/join-command.sh")

# Join remaining dedicated nodes
echo "Joining remaining dedicated nodes..."
for ip in "${DEDICATED_ARRAY[@]:1}"; do
    echo "Joining node $ip..."
    ssh -o StrictHostKeyChecking=no ec2-user@$ip << EOF
sudo $JOIN_CMD
EOF
done

# Join default tenancy nodes
echo "Joining default tenancy nodes..."
for ip in "${DEFAULT_ARRAY[@]}"; do
    echo "Joining node $ip..."
    ssh -o StrictHostKeyChecking=no ec2-user@$ip << EOF
sudo $JOIN_CMD
EOF
done

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
export KUBECONFIG=~/.kube/config-$CLUSTER_NAME
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Cluster setup complete!"
echo "Use: export KUBECONFIG=~/.kube/config-$CLUSTER_NAME"
echo "Then: kubectl get nodes -o wide"