#!/bin/bash

set -e

echo "Waiting for EC2 instances to complete initialization..."

# Get instance IPs
DEDICATED_IPS=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[]')
DEFAULT_IPS=$(terraform -chdir=terraform output -json default_node_ips | jq -r '.[]')

ALL_IPS=($DEDICATED_IPS $DEFAULT_IPS)

echo "Checking nodes: ${ALL_IPS[@]}"

# Function to check if kubeadm is installed
check_node() {
    local ip=$1
    echo "Checking node $ip..."
    
    # Try to connect and check if kubeadm exists
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$ip "which kubeadm" &>/dev/null; then
        echo "✓ Node $ip is ready"
        return 0
    else
        echo "✗ Node $ip not ready yet"
        return 1
    fi
}

# Wait for all nodes to be ready
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    all_ready=true
    
    for ip in "${ALL_IPS[@]}"; do
        if ! check_node $ip; then
            all_ready=false
        fi
    done
    
    if [ "$all_ready" = true ]; then
        echo "All nodes are ready!"
        break
    fi
    
    attempt=$((attempt + 1))
    echo "Attempt $attempt/$max_attempts - waiting 30 seconds..."
    sleep 30
done

if [ $attempt -eq $max_attempts ]; then
    echo "Timeout waiting for nodes to be ready"
    exit 1
fi

echo "All nodes initialized successfully!"