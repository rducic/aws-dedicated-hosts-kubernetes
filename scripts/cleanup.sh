#!/bin/bash

# AWS Dedicated Hosts Kubernetes Demo - Complete Cleanup Script
# This script performs a comprehensive cleanup of all resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if terraform directory exists
check_terraform_dir() {
    if [ ! -d "terraform" ]; then
        error "Terraform directory not found. Please run this script from the project root."
        exit 1
    fi
}

# Function to get master node IP for Kubernetes cleanup
get_master_ip() {
    cd terraform
    if [ -f "terraform.tfstate" ]; then
        terraform output -raw master_public_ip 2>/dev/null || echo ""
    else
        echo ""
    fi
    cd ..
}

# Function to clean up Kubernetes resources
cleanup_kubernetes() {
    local master_ip="$1"
    
    if [ -z "$master_ip" ]; then
        warn "No master IP found. Skipping Kubernetes cleanup."
        return 0
    fi
    
    log "Cleaning up Kubernetes resources on master node: $master_ip"
    
    # Test SSH connectivity
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ec2-user@"$master_ip" "echo 'SSH connection successful'" 2>/dev/null; then
        warn "Cannot connect to master node. Skipping Kubernetes cleanup."
        return 0
    fi
    
    # Clean up demo namespace and resources
    log "Removing demo namespace and applications..."
    ssh -o StrictHostKeyChecking=no ec2-user@"$master_ip" "
        kubectl delete namespace demo --ignore-not-found=true
        kubectl delete -f k8s/dashboard.yaml --ignore-not-found=true 2>/dev/null || true
        kubectl delete -f k8s/grafana.yaml --ignore-not-found=true 2>/dev/null || true
        kubectl delete -f k8s/cluster-info.yaml --ignore-not-found=true 2>/dev/null || true
        kubectl delete priorityclass dedicated-priority overflow-priority --ignore-not-found=true 2>/dev/null || true
    " 2>/dev/null || warn "Some Kubernetes resources may not have been cleaned up"
    
    success "Kubernetes resources cleanup completed"
}

# Function to destroy Terraform infrastructure
cleanup_terraform() {
    log "Destroying Terraform infrastructure..."
    
    cd terraform
    
    # Check if terraform state exists
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        warn "No Terraform state found. Infrastructure may already be destroyed."
        cd ..
        return 0
    fi
    
    # Initialize terraform if needed
    if [ ! -d ".terraform" ]; then
        log "Initializing Terraform..."
        terraform init
    fi
    
    # Destroy infrastructure
    log "Running terraform destroy..."
    if terraform destroy -auto-approve; then
        success "Terraform infrastructure destroyed successfully"
    else
        error "Terraform destroy failed. You may need to manually clean up resources."
        cd ..
        return 1
    fi
    
    cd ..
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove Terraform state and cache files
    if [ -d "terraform/.terraform" ]; then
        log "Removing Terraform cache directory..."
        rm -rf terraform/.terraform
    fi
    
    if [ -f "terraform/terraform.tfstate" ]; then
        log "Removing Terraform state file..."
        rm -f terraform/terraform.tfstate
    fi
    
    if [ -f "terraform/terraform.tfstate.backup" ]; then
        log "Removing Terraform state backup..."
        rm -f terraform/terraform.tfstate.backup
    fi
    
    # Remove any temporary files
    find . -name "*.tmp" -type f -delete 2>/dev/null || true
    find . -name ".DS_Store" -type f -delete 2>/dev/null || true
    
    # Clean up any log files
    find . -name "*.log" -type f -delete 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Function to clean up SSH known_hosts entries
cleanup_ssh_known_hosts() {
    local master_ip="$1"
    
    if [ -n "$master_ip" ] && [ -f "$HOME/.ssh/known_hosts" ]; then
        log "Cleaning up SSH known_hosts entries..."
        ssh-keygen -R "$master_ip" 2>/dev/null || true
        success "SSH known_hosts cleaned up"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local issues=0
    
    # Check for remaining Terraform files
    if [ -f "terraform/terraform.tfstate" ] || [ -f "terraform/terraform.tfstate.backup" ]; then
        warn "Terraform state files still exist"
        issues=$((issues + 1))
    fi
    
    if [ -d "terraform/.terraform" ]; then
        warn "Terraform cache directory still exists"
        issues=$((issues + 1))
    fi
    
    # Check for AWS resources (if AWS CLI is available)
    if command -v aws >/dev/null 2>&1; then
        log "Checking for remaining AWS resources..."
        
        # Check for EC2 instances with our tags
        local instances=$(aws ec2 describe-instances \
            --filters "Name=tag:Project,Values=dedicated-hosts-k8s-demo" \
                     "Name=instance-state-name,Values=running,pending,stopping,stopped" \
            --query 'Reservations[*].Instances[*].InstanceId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$instances" ] && [ "$instances" != "None" ]; then
            warn "Found remaining EC2 instances: $instances"
            issues=$((issues + 1))
        fi
        
        # Check for Dedicated Hosts
        local hosts=$(aws ec2 describe-hosts \
            --query 'Hosts[?State==`available`].HostId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$hosts" ] && [ "$hosts" != "None" ]; then
            warn "Found remaining Dedicated Hosts: $hosts"
            issues=$((issues + 1))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        success "Cleanup verification completed successfully"
        return 0
    else
        warn "Cleanup verification found $issues potential issues"
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting comprehensive cleanup of AWS Dedicated Hosts Kubernetes Demo"
    log "=================================================="
    
    # Check prerequisites
    check_terraform_dir
    
    # Get master IP before destroying infrastructure
    local master_ip
    master_ip=$(get_master_ip)
    
    # Perform cleanup steps
    log "Step 1: Kubernetes Resources Cleanup"
    cleanup_kubernetes "$master_ip"
    
    log "Step 2: Terraform Infrastructure Cleanup"
    cleanup_terraform
    
    log "Step 3: Local Files Cleanup"
    cleanup_local_files
    
    log "Step 4: SSH Known Hosts Cleanup"
    cleanup_ssh_known_hosts "$master_ip"
    
    log "Step 5: Verification"
    if verify_cleanup; then
        success "=================================================="
        success "Cleanup completed successfully!"
        success "All resources have been removed and files cleaned up."
        success "You can now safely commit your changes or redeploy."
    else
        warn "=================================================="
        warn "Cleanup completed with some warnings."
        warn "Please review the warnings above and manually clean up if needed."
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"