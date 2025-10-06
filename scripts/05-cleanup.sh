#!/bin/bash

# Clean up all resources
set -e

echo "🧹 Cleaning Up AWS Dedicated Hosts Demo"
echo "======================================="

# Stop any running load generation
echo "⏹️  Stopping load generation..."
kubectl delete deployment --all -n demo --insecure-skip-tls-verify 2>/dev/null || true

# Destroy infrastructure
echo "💥 Destroying infrastructure..."
cd terraform
terraform destroy -auto-approve

echo "🧹 Cleaning up local files..."
rm -f ~/.kube/config

echo ""
echo "✅ Cleanup complete!"
echo "All AWS resources have been destroyed."

cd ..