terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variables
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "dedicated-hosts-demo"
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "dedicated-hosts-vpc"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "dedicated-hosts-igw"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_subnet" "public" {
  count = 2
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "public-subnet-${count.index + 1}"
    Project = "dedicated-hosts-demo"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = {
    Name = "public-rt"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_route_table_association" "public" {
  count = 2
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "k8s_nodes" {
  name_prefix = "k8s-nodes-"
  vpc_id      = aws_vpc.main.id
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Kubernetes API server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Node communication
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    self      = true
  }
  
  # Pod network
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }
  
  # Management UIs
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "k8s-nodes-sg"
    Project = "dedicated-hosts-demo"
  }
}

# Key Pair
resource "aws_key_pair" "demo" {
  key_name   = "k8s-demo-key"
  public_key = file("~/.ssh/id_rsa.pub")
  
  tags = {
    Name = "k8s-demo-key"
    Project = "dedicated-hosts-demo"
  }
}

# Master Node (Default Tenancy for Cost Optimization)
resource "aws_instance" "master" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "m5.large"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  subnet_id             = aws_subnet.public[0].id
  
  # Master on default tenancy for cost optimization
  tenancy = "default"
  
  user_data = base64encode(templatefile("${path.module}/user-data-master.sh", {
    cluster_name = var.cluster_name
  }))

  tags = {
    Name    = "k8s-master"
    Project = "dedicated-hosts-demo"
    Type    = "master"
    Role    = "control-plane"
  }
}

# Dedicated Hosts (2 hosts for worker nodes)
resource "aws_ec2_host" "dedicated" {
  count = 2
  
  availability_zone = data.aws_availability_zones.available.names[count.index]
  instance_type     = "m5.large"
  
  tags = {
    Name = "dedicated-host-${count.index + 1}"
    Project = "dedicated-hosts-demo"
    Zone = data.aws_availability_zones.available.names[count.index]
  }
}

# Dedicated Host Worker Nodes (2 instances)
resource "aws_instance" "dedicated_workers" {
  count                  = 2
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "m5.large"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  subnet_id             = aws_subnet.public[count.index % 2].id
  
  # Place on dedicated hosts
  tenancy = "host"
  host_id = aws_ec2_host.dedicated[count.index].id
  
  user_data = base64encode(templatefile("${path.module}/user-data-dedicated.sh", {
    cluster_name = var.cluster_name
    node_name = "k8s-dedicated-${count.index + 1}"
    master_ip = aws_instance.master.private_ip
  }))

  tags = {
    Name    = "k8s-dedicated-${count.index + 1}"
    Project = "dedicated-hosts-demo"
    Type    = "dedicated-host"
    Role    = "worker"
  }
  
  depends_on = [aws_instance.master]
}

# Default Tenancy Worker Nodes (2 instances for spillover)
resource "aws_instance" "default_workers" {
  count                  = 2
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "m5.large"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  subnet_id             = aws_subnet.public[count.index % 2].id
  
  # Default tenancy for cost-effective spillover
  tenancy = "default"
  
  user_data = base64encode(templatefile("${path.module}/user-data-default.sh", {
    cluster_name = var.cluster_name
    node_name = "k8s-default-${count.index + 1}"
    master_ip = aws_instance.master.private_ip
  }))

  tags = {
    Name    = "k8s-default-${count.index + 1}"
    Project = "dedicated-hosts-demo"
    Type    = "default-tenancy"
    Role    = "worker"
  }
  
  depends_on = [aws_instance.master]
}

# Outputs
output "master_public_ip" {
  description = "Public IP of the master node"
  value       = aws_instance.master.public_ip
}

output "dedicated_worker_ips" {
  description = "Public IPs of dedicated host worker nodes"
  value       = aws_instance.dedicated_workers[*].public_ip
}

output "default_worker_ips" {
  description = "Public IPs of default tenancy worker nodes"
  value       = aws_instance.default_workers[*].public_ip
}

output "dedicated_host_ids" {
  description = "IDs of the dedicated hosts"
  value       = aws_ec2_host.dedicated[*].id
}

output "cluster_info" {
  description = "Cluster connection information"
  value = {
    master_ip = aws_instance.master.public_ip
    cluster_name = var.cluster_name
    ssh_command = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.master.public_ip}"
  }
}