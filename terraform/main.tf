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

variable "admin_ip" {
  description = "Admin IP address for RDP and K8s access"
  type        = string
  default     = "73.136.134.34/32"
}

variable "dedicated_worker_count" {
  description = "Number of dedicated host worker instances"
  type        = number
  default     = 5
}

variable "default_worker_count" {
  description = "Number of default tenancy worker instances"
  type        = number
  default     = 0
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

data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
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

resource "aws_subnet" "private" {
  count = 2
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = {
    Name = "private-subnet-${count.index + 1}"
    Project = "dedicated-hosts-demo"
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

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = {
    Name = "nat-gateway-eip"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  
  tags = {
    Name = "main-nat-gateway"
    Project = "dedicated-hosts-demo"
  }
  
  depends_on = [aws_internet_gateway.main]
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  
  tags = {
    Name = "private-rt"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_route_table_association" "private" {
  count = 2
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "windows_rdp" {
  name_prefix = "windows-rdp-"
  vpc_id      = aws_vpc.main.id
  
  # RDP access from admin IP only
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  
  # SSH access from admin IP only (for management)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "windows-rdp-sg"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_security_group" "k8s_master" {
  name_prefix = "k8s-master-"
  vpc_id      = aws_vpc.main.id
  
  # SSH access from admin IP and Windows RDP server
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.windows_rdp.id]
  }
  
  # Kubernetes API server from admin IP and Windows RDP server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  
  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.windows_rdp.id]
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
  
  # Management UIs from admin IP and Windows RDP server
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  
  ingress {
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.windows_rdp.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "k8s-master-sg"
    Project = "dedicated-hosts-demo"
  }
}

resource "aws_security_group" "k8s_workers" {
  name_prefix = "k8s-workers-"
  vpc_id      = aws_vpc.main.id
  
  # SSH access from Windows RDP server only (no direct access)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.windows_rdp.id]
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
  
  # Communication with master
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_master.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "k8s-workers-sg"
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

# Windows RDP Bastion Host
resource "aws_instance" "windows_rdp" {
  ami                    = data.aws_ami.windows_server.id
  instance_type          = "t3.medium"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.windows_rdp.id]
  subnet_id             = aws_subnet.public[0].id
  
  # Enable detailed monitoring
  monitoring = true
  
  # User data to configure RDP and install tools
  user_data = base64encode(templatefile("${path.module}/user-data-windows.ps1", {
    admin_password = "K8sDemo2024!"
  }))

  tags = {
    Name    = "windows-rdp-bastion"
    Project = "dedicated-hosts-demo"
    Type    = "bastion"
    Role    = "management"
  }
}

# Master Node (Default Tenancy for Cost Optimization)
resource "aws_instance" "master" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "m5.large"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.k8s_master.id]
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

# Dedicated Host Worker Nodes (variable count for phased deployment)
resource "aws_instance" "dedicated_workers" {
  count                  = var.dedicated_worker_count
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "m5.large"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id             = aws_subnet.private[count.index % 2].id
  
  # Place on dedicated hosts (distribute across 2 hosts)
  tenancy = "host"
  host_id = aws_ec2_host.dedicated[count.index % 2].id
  
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
  
  depends_on = [aws_instance.master, aws_nat_gateway.main]
}

# Default Tenancy Worker Nodes (variable count for spillover demo)
resource "aws_instance" "default_workers" {
  count                  = var.default_worker_count
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "m5.large"
  key_name              = aws_key_pair.demo.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id             = aws_subnet.private[count.index % 2].id
  
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
  
  depends_on = [aws_instance.master, aws_nat_gateway.main]
}

# Outputs
output "windows_rdp_info" {
  description = "Windows RDP server connection information"
  value = {
    public_ip = aws_instance.windows_rdp.public_ip
    private_ip = aws_instance.windows_rdp.private_ip
    rdp_command = "mstsc /v:${aws_instance.windows_rdp.public_ip}"
    username = "Administrator"
    password = "K8sDemo2024!"
  }
}

output "master_info" {
  description = "Kubernetes master node information"
  value = {
    public_ip = aws_instance.master.public_ip
    private_ip = aws_instance.master.private_ip
    ssh_command = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.master.public_ip}"
  }
}

output "dedicated_worker_private_ips" {
  description = "Private IPs of dedicated host worker nodes"
  value       = aws_instance.dedicated_workers[*].private_ip
}

output "default_worker_private_ips" {
  description = "Private IPs of default tenancy worker nodes"
  value       = aws_instance.default_workers[*].private_ip
}

output "dedicated_host_ids" {
  description = "IDs of the dedicated hosts"
  value       = aws_ec2_host.dedicated[*].id
}

output "security_summary" {
  description = "Security configuration summary"
  value = {
    admin_ip_allowed = var.admin_ip
    rdp_access = "Only from ${var.admin_ip}"
    k8s_api_access = "Only from ${var.admin_ip} and Windows RDP server"
    worker_nodes = "Private subnets only, no direct internet access"
  }
}