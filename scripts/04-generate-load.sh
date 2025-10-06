#!/bin/bash

# Generate CPU load to demonstrate high utilization on dedicated hosts
set -e

echo "🔥 Generating CPU Load on Dedicated Hosts"
echo "========================================="

# Scale up demo applications to fill dedicated hosts
echo "📈 Scaling demo applications..."
kubectl patch deployment demo-app-dedicated -n demo -p '{"spec":{"replicas":10}}' --insecure-skip-tls-verify
kubectl patch deployment demo-app-overflow -n demo -p '{"spec":{"replicas":15}}' --insecure-skip-tls-verify

# Wait for scheduling
echo "⏳ Waiting for pods to schedule..."
sleep 60

# Show current distribution
echo "📊 Current pod distribution:"
kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep Running | awk '{print $7}' | sort | uniq -c

# Generate CPU load on existing pods
echo "🔥 Generating CPU load on dedicated host pods..."

# Get pods running on dedicated hosts
DEDICATED_PODS=$(kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep k8s-dedicated | grep Running | awk '{print $1}')

if [ -z "$DEDICATED_PODS" ]; then
    echo "❌ No pods running on dedicated hosts yet. Waiting..."
    sleep 30
    DEDICATED_PODS=$(kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep k8s-dedicated | grep Running | awk '{print $1}')
fi

# Start CPU load in each pod
for pod in $DEDICATED_PODS; do
    echo "🚀 Starting CPU load in pod: $pod"
    kubectl exec -n demo $pod --insecure-skip-tls-verify -- /bin/sh -c '
        # Kill any existing CPU load processes
        pkill -f "cpu_burn" 2>/dev/null || true
        
        # Start CPU-intensive background processes
        (
            while true; do
                # CPU burn loop
                i=0
                while [ $i -lt 100000 ]; do
                    result=$((i * i * i))
                    i=$((i + 1))
                done
            done
        ) &
        
        (
            while true; do
                # More CPU load
                for j in $(seq 1 50000); do
                    echo "cpu_burn_$j" > /dev/null
                done
            done
        ) &
        
        echo "CPU load started"
    ' &
    sleep 2
done

echo ""
echo "✅ CPU load generation started!"
echo ""

# Monitor results
echo "📊 Monitoring CPU utilization (30 cycles):"
for i in {1..30}; do
    echo "$(date): Monitoring cycle $i/30"
    
    echo "Resource utilization:"
    kubectl top nodes --insecure-skip-tls-verify 2>/dev/null || echo "Metrics server not ready"
    
    echo "Pod distribution:"
    kubectl get pods -n demo -o wide --insecure-skip-tls-verify | grep Running | awk '{print $7}' | sort | uniq -c
    
    echo "---"
    sleep 10
done

echo ""
echo "🎉 Load generation complete!"
echo ""
echo "🎯 Final Results:"
kubectl top nodes --insecure-skip-tls-verify 2>/dev/null || echo "Run 'kubectl top nodes' to see final utilization"