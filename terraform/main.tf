terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
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
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "dedicated-hosts-igw"
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
  
  # Kubernetes API server (allow from anywhere for demo)
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
  
  # Kubernetes Dashboard
  ingress {
    from_port   = 30443
    to_port     = 30443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Grafana
  ingress {
    from_port   = 30300
    to_port     = 30300
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Cluster Info Web Interface
  ingress {
    from_port   = 30080
    to_port     = 30080
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
  }
}

# Key Pair
resource "aws_key_pair" "k8s" {
  key_name   = "k8s-demo-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Dedicated Hosts
resource "aws_ec2_host" "dedicated" {
  count = 2
  
  availability_zone = data.aws_availability_zones.available.names[count.index]
  instance_type     = "m5.large"
  
  tags = {
    Name = "dedicated-host-${count.index + 1}"
    Zone = data.aws_availability_zones.available.names[count.index]
  }
}

# Launch Template for Dedicated Host Instances
resource "aws_launch_template" "dedicated_nodes" {
  name_prefix   = "k8s-dedicated-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "m5.large"
  key_name      = aws_key_pair.k8s.key_name
  
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  
  placement {
    tenancy = "host"
  }
  
  user_data = base64encode(templatefile("${path.module}/user-data-dedicated.sh", {
    cluster_name = var.cluster_name
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "k8s-dedicated-node"
      Type = "dedicated"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }
}

# Launch Template for Default Tenancy Instances
resource "aws_launch_template" "default_nodes" {
  name_prefix   = "k8s-default-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "m5.large"
  key_name      = aws_key_pair.k8s.key_name
  
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  
  user_data = base64encode(templatefile("${path.module}/user-data-default.sh", {
    cluster_name = var.cluster_name
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "k8s-default-node"
      Type = "default"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }
}

# Dedicated Host Instances
resource "aws_instance" "dedicated_nodes" {
  count = 2
  
  launch_template {
    id      = aws_launch_template.dedicated_nodes.id
    version = "$Latest"
  }
  
  subnet_id = aws_subnet.public[count.index].id
  host_id   = aws_ec2_host.dedicated[count.index].id
  
  tags = {
    Name = "k8s-dedicated-node-${count.index + 1}"
    Zone = data.aws_availability_zones.available.names[count.index]
  }
}

# Default Tenancy Instances (for overflow)
resource "aws_instance" "default_nodes" {
  count = 2
  
  launch_template {
    id      = aws_launch_template.default_nodes.id
    version = "$Latest"
  }
  
  subnet_id = aws_subnet.public[count.index].id
  
  tags = {
    Name = "k8s-default-node-${count.index + 1}"
    Zone = data.aws_availability_zones.available.names[count.index]
  }
}