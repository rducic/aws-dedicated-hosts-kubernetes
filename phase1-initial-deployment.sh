#!/bin/bash

# Phase 1: Initial deployment with 5 dedicated host workers
set -e

echo "🚀 Phase 1: Initial Deployment"
echo "=============================="
echo "Deploying basic infrastructure with 5 dedicated host workers"

cd terraform

# Deploy with initial configuration
terraform init
terraform apply -var="dedicated_worker_count=5" -var="default_worker_count=0" -auto-approve

# Get master IP
MASTER_IP=$(terraform output -json master_info | jq -r '.public_ip')
echo "Master IP: $MASTER_IP"

echo "⏳ Waiting for instances to initialize (3 minutes)..."
sleep 180

echo "✅ Phase 1 deployment complete!"
echo "📊 Infrastructure Summary:"
echo "- 1 Master node"
echo "- 5 Dedicated host workers (on 2 dedicated hosts)"
echo "- 0 Default tenancy workers"
echo ""
echo "🔧 Next step: Run ./phase2-join-workers.sh"

cd ..