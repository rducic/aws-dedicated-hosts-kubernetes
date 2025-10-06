#!/bin/bash

# Demonstrate spillover behavior
set -e

echo "🌊 Demonstrating Spillover Behavior"
echo "==================================="

echo "📊 Current cluster status:"
kubectl get nodes --insecure-skip-tls-verify

echo ""
echo "📦 Current pod distribution:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify

echo ""
echo "🚀 Scaling workload to trigger spillover..."
kubectl scale deployment cpu-load-app --replicas=100 -n demo --insecure-skip-tls-verify

echo ""
echo "⏳ Waiting for pods to schedule..."
sleep 30

echo ""
echo "📊 Pod distribution after scaling:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify | head -20

echo ""
echo "🎯 Spillover Summary:"
echo "===================="
echo "Pods on dedicated hosts:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep dedicated | wc -l

echo "Pods on default tenancy:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep default | wc -l

echo "Pending pods (no capacity):"
kubectl get pods -n demo --insecure-skip-tls-verify | grep Pending | wc -l

echo ""
echo "✅ Spillover demonstration complete!"
echo "💡 This shows how workloads spill over from dedicated hosts to default tenancy when capacity is full."