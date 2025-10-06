#!/bin/bash

# User data script for default tenancy worker instances
set -e

# Update system
yum update -y
yum install -y docker

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install kubeadm, kubelet
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

yum install -y kubelet kubeadm
systemctl enable kubelet

# Configure kubelet for default tenancy
echo 'KUBELET_EXTRA_ARGS="--node-labels=tenancy=default,node-type=default-tenancy"' > /etc/sysconfig/kubelet

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure container runtime
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker

# Set hostname
hostnamectl set-hostname ${node_name}

# Wait for master to be ready
sleep 180

# Create join script
cat > /tmp/join_cluster.sh <<'JOINEOF'
#!/bin/bash
set -e

# Wait for master to be accessible
for i in {1..30}; do
    if curl -k https://${master_ip}:6443/healthz &>/dev/null; then
        echo "Master is ready"
        break
    fi
    echo "Waiting for master... attempt $i/30"
    sleep 10
done

# Ready to join - manual step required
echo "Ready to join cluster. Manual join required."
echo "Run on master: kubeadm token create --print-join-command"
echo "Then run the output on this node: ${node_name}"
JOINEOF

chmod +x /tmp/join_cluster.sh
/tmp/join_cluster.sh &

echo "Default tenancy worker node setup complete"