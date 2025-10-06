#!/bin/bash

set -e

echo "Checking Management UI Access..."

# Get master node IP
MASTER_IP=$(terraform -chdir=terraform output -json dedicated_node_ips | jq -r '.[0]')

echo "Master node IP: $MASTER_IP"
echo ""

# Check if services are running
echo "=== Service Status ==="
ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl get svc -A | grep -E '(dashboard|grafana|cluster-info)'"

echo ""
echo "=== Pod Status ==="
ssh -o StrictHostKeyChecking=no ec2-user@$MASTER_IP "kubectl get pods -A | grep -E '(dashboard|grafana|cluster-info)'"

echo ""
echo "=== Security Group Update Required ==="
echo "The management UIs are deployed but may not be accessible externally."
echo "You need to update the security group to allow these ports:"
echo ""
echo "Required Security Group Rules:"
echo "- Port 30443 (HTTPS) - Kubernetes Dashboard"
echo "- Port 30300 (HTTP)  - Grafana"
echo "- Port 30080 (HTTP)  - Cluster Info"
echo ""
echo "To update security group manually:"
echo "1. Go to AWS Console → EC2 → Security Groups"
echo "2. Find the security group used by your instances (k8s-nodes-*)"
echo "3. Add inbound rules for ports 30080, 30300, and 30443 from 0.0.0.0/0"
echo ""
echo "Or use AWS CLI:"
echo "aws ec2 authorize-security-group-ingress --group-id <SG-ID> --protocol tcp --port 30080 --cidr 0.0.0.0/0"
echo "aws ec2 authorize-security-group-ingress --group-id <SG-ID> --protocol tcp --port 30300 --cidr 0.0.0.0/0"
echo "aws ec2 authorize-security-group-ingress --group-id <SG-ID> --protocol tcp --port 30443 --cidr 0.0.0.0/0"
echo ""
echo "Once updated, access the UIs at:"
echo "- Kubernetes Dashboard: https://$MASTER_IP:30443"
echo "- Grafana: http://$MASTER_IP:30300"
echo "- Cluster Info: http://$MASTER_IP:30080"