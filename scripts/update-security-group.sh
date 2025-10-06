#!/bin/bash

set -e

echo "Updating Security Group for Management UI Access..."

# Get the security group ID from running instances
SECURITY_GROUP_ID=$(aws ec2 describe-instances --region us-west-2 \
    --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=k8s-*" \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

if [ "$SECURITY_GROUP_ID" = "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
    echo "Error: Could not find security group ID for Kubernetes instances"
    exit 1
fi

echo "Found security group: $SECURITY_GROUP_ID"

# Ports to add
PORTS=(30080 30300 30443)
PORT_DESCRIPTIONS=("Cluster Info Web Interface" "Grafana" "Kubernetes Dashboard")

for i in "${!PORTS[@]}"; do
    PORT=${PORTS[$i]}
    DESC=${PORT_DESCRIPTIONS[$i]}
    
    echo "Adding rule for port $PORT ($DESC)..."
    
    # Check if rule already exists
    EXISTING=$(aws ec2 describe-security-groups --region us-west-2 \
        --group-ids $SECURITY_GROUP_ID \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$PORT\` && ToPort==\`$PORT\`]" \
        --output text)
    
    if [ -z "$EXISTING" ]; then
        aws ec2 authorize-security-group-ingress --region us-west-2 \
            --group-id $SECURITY_GROUP_ID \
            --protocol tcp \
            --port $PORT \
            --cidr 0.0.0.0/0 > /dev/null
        echo "✅ Added rule for port $PORT"
    else
        echo "ℹ️  Rule for port $PORT already exists"
    fi
done

echo ""
echo "Security group update complete!"
echo ""
echo "Management UIs are now accessible at:"
echo "- 🎛️  Kubernetes Dashboard: https://$(terraform -chdir=terraform output -raw dedicated_node_ips | jq -r '.[0]'):30443"
echo "- 📊 Grafana: http://$(terraform -chdir=terraform output -raw dedicated_node_ips | jq -r '.[0]'):30300"
echo "- ℹ️  Cluster Info: http://$(terraform -chdir=terraform output -raw dedicated_node_ips | jq -r '.[0]'):30080"
echo ""
echo "For dashboard access token, run:"
echo "ssh ec2-user@$(terraform -chdir=terraform output -raw dedicated_node_ips | jq -r '.[0]') \"kubectl -n kubernetes-dashboard create token admin-user --duration=24h\""