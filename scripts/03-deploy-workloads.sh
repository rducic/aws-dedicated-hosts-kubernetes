#!/bin/bash

# Deploy demo workloads to demonstrate spillover behavior
set -e

echo "🚀 Deploying Demo Workloads"
echo "==========================="

# Deploy demo applications
echo "📦 Deploying demo applications..."
kubectl apply -f k8s/demo-app.yaml --insecure-skip-tls-verify

# Deploy load generator
echo "⚡ Deploying load generator..."
kubectl apply -f k8s/load-generator.yaml --insecure-skip-tls-verify

# Deploy management UIs
echo "🖥️  Deploying management UIs..."
kubectl apply -f k8s/dashboard.yaml --insecure-skip-tls-verify
kubectl apply -f k8s/metrics-server.yaml --insecure-skip-tls-verify
kubectl apply -f k8s/cluster-info.yaml --insecure-skip-tls-verify

# Wait for pods to start
echo "⏳ Waiting for pods to start..."
sleep 60

# Show initial deployment
echo "📊 Initial workload deployment:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify

echo ""
echo "🎯 Pod distribution by node:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep Running | awk '{print $7}' | sort | uniq -c

echo ""
echo "✅ Workloads deployed successfully!"
echo ""
echo "🔧 Next step:"
echo "Run: ./scripts/04-generate-load.sh"