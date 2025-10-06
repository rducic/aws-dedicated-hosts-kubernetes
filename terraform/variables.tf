variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "dedicated-hosts-demo"
}

variable "instance_type" {
  description = "EC2 instance type for nodes"
  type        = string
  default     = "m5.large"
}