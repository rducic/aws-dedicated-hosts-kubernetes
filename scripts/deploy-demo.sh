#!/bin/bash

set -e

CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name)
export KUBECONFIG=~/.kube/config-$CLUSTER_NAME

echo "Deploying demo application..."

# Apply Kubernetes manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/priority-class.yaml
kubectl apply -f k8s/demo-app.yaml
kubectl apply -f k8s/service.yaml

echo "Waiting for pods to be scheduled..."
sleep 10

# Show pod distribution
echo "Pod distribution across nodes:"
kubectl get pods -n demo -o wide

echo ""
echo "Node information:"
kubectl get nodes -o custom-columns="NAME:.metadata.name,TENANCY:.metadata.labels.tenancy,TYPE:.metadata.labels.node-type,TAINTS:.spec.taints[*].key"

echo ""
echo "Dedicated host pods:"
kubectl get pods -n demo -l tier=dedicated -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase"

echo ""
echo "Overflow pods:"
kubectl get pods -n demo -l tier=overflow -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase"