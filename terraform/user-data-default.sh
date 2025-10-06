#!/bin/bash

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install kubeadm, kubelet, kubectl
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet

# Configure node labels and taints for default tenancy
echo 'KUBELET_EXTRA_ARGS="--node-labels=node-type=default-tenancy"' > /etc/sysconfig/kubelet

# Set hostname
hostnamectl set-hostname ${node_name}

# Wait for master to be ready (simple check)
while ! curl -k https://${master_ip}:6443/healthz; do
  echo "Waiting for master node to be ready..."
  sleep 30
done

# Note: The actual kubeadm join will be done manually or via a separate script
# since the token needs to be generated dynamically

# Create a script for manual join
cat > /home/ec2-user/join-cluster.sh << 'EOL'
#!/bin/bash
# This script should be run with the appropriate kubeadm join command
# Example: sudo kubeadm join MASTER_IP:6443 --token TOKEN --discovery-token-ca-cert-hash HASH --node-name=${node_name}
echo "Run this script with the kubeadm join command from the master node"
EOL

chmod +x /home/ec2-user/join-cluster.sh
chown ec2-user:ec2-user /home/ec2-user/join-cluster.sh