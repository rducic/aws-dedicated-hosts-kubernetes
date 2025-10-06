#!/bin/bash

set -e

echo "Cleaning up demo resources..."

CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name 2>/dev/null || echo "")

if [ ! -z "$CLUSTER_NAME" ]; then
    export KUBECONFIG=~/.kube/config-$CLUSTER_NAME
    
    echo "Deleting Kubernetes resources..."
    kubectl delete namespace demo --ignore-not-found=true
    kubectl delete priorityclass dedicated-host-priority --ignore-not-found=true
    kubectl delete priorityclass default-tenancy-priority --ignore-not-found=true
    
    echo "Removing kubeconfig..."
    rm -f ~/.kube/config-$CLUSTER_NAME
fi

echo "Destroying Terraform infrastructure..."
terraform -chdir=terraform destroy -auto-approve

echo "Cleanup complete!"