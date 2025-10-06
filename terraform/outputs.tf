output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "dedicated_host_ids" {
  description = "Dedicated Host IDs"
  value       = aws_ec2_host.dedicated[*].id
}

output "dedicated_node_ips" {
  description = "Dedicated node public IPs"
  value       = aws_instance.dedicated_nodes[*].public_ip
}

output "default_node_ips" {
  description = "Default tenancy node public IPs"
  value       = aws_instance.default_nodes[*].public_ip
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = var.cluster_name
}