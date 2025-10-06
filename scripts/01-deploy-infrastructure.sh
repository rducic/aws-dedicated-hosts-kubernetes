#!/bin/bash

# Deploy the complete AWS Dedicated Hosts infrastructure
set -e

echo "🚀 Deploying AWS Dedicated Hosts with Kubernetes Infrastructure"
echo "=============================================================="

# Initialize and apply Terraform
echo "📋 Initializing Terraform..."
cd terraform
terraform init

echo "🏗️  Planning infrastructure deployment..."
terraform plan

echo "🚀 Deploying infrastructure..."
terraform apply -auto-approve

echo "📊 Infrastructure deployment complete!"
echo ""

# Get outputs
MASTER_IP=$(terraform output -raw master_public_ip)
DEDICATED_IPS=$(terraform output -json dedicated_worker_ips | jq -r '.[]')
DEFAULT_IPS=$(terraform output -json default_worker_ips | jq -r '.[]')

echo "🎯 Infrastructure Summary:"
echo "========================="
echo "Master Node: $MASTER_IP"
echo "Dedicated Workers: $DEDICATED_IPS"
echo "Default Workers: $DEFAULT_IPS"
echo ""

echo "⏳ Waiting for instances to initialize (5 minutes)..."
sleep 300

echo "✅ Infrastructure deployment complete!"
echo ""
echo "🔧 Next steps:"
echo "1. Run: ./scripts/02-setup-cluster.sh"
echo "2. Run: ./scripts/03-deploy-workloads.sh"
echo "3. Run: ./scripts/04-generate-load.sh"

cd ..