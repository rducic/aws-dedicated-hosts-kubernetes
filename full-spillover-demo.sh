#!/bin/bash

# Complete spillover demonstration - all phases
set -e

echo "🎯 Complete AWS Dedicated Hosts Spillover Demonstration"
echo "======================================================="
echo ""
echo "This demo will show:"
echo "1. Initial deployment (5 dedicated workers)"
echo "2. Scale to 100% utilization (96 dedicated workers)"
echo "3. Add spillover capacity (2 default tenancy workers)"
echo "4. Demonstrate workload spillover behavior"
echo ""

read -p "Press Enter to start Phase 1 (Initial Deployment)..."
./phase1-initial-deployment.sh

echo ""
read -p "Press Enter to start Phase 2 (Join Workers & Setup Cluster)..."
./phase2-join-workers.sh

echo ""
read -p "Press Enter to start Phase 3 (Scale to 100%)..."
./phase3-scale-to-100-percent.sh

echo ""
read -p "Press Enter to start Phase 4 (Add Spillover)..."
./phase4-add-spillover.sh

echo ""
read -p "Press Enter to demonstrate spillover behavior..."
./demonstrate-spillover.sh

echo ""
echo "🎉 Complete spillover demonstration finished!"
echo ""
echo "🧹 To clean up all resources, run: ./scripts/05-cleanup.sh"