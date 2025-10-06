#!/bin/bash

set -e

CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name)
export KUBECONFIG=~/.kube/config-$CLUSTER_NAME

echo "Testing pod scaling and placement..."

# Scale up dedicated tier to fill dedicated hosts
echo "Scaling dedicated tier to 12 replicas..."
kubectl scale deployment demo-app-dedicated --replicas=12 -n demo

echo "Waiting for pods to be scheduled..."
sleep 30

echo "Current pod distribution:"
kubectl get pods -n demo -o wide

echo ""
echo "Pods per node:"
kubectl get pods -n demo -o json | jq -r '.items[] | "\(.spec.nodeName) \(.metadata.labels.tier)"' | sort | uniq -c

# Scale up even more to force overflow
echo ""
echo "Scaling dedicated tier to 16 replicas to force overflow..."
kubectl scale deployment demo-app-dedicated --replicas=16 -n demo

echo "Waiting for scheduling..."
sleep 30

echo "Final pod distribution:"
kubectl get pods -n demo -o wide

echo ""
echo "Pods per node (final):"
kubectl get pods -n demo -o json | jq -r '.items[] | "\(.spec.nodeName) \(.metadata.labels.tier)"' | sort | uniq -c

echo ""
echo "Pending pods (if any):"
kubectl get pods -n demo --field-selector=status.phase=Pending