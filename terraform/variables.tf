variable "aws_region" {
  description = "AWS region (Frankfurt)"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "k8s-frankfurt"
}

variable "instance_type" {
  description = "EC2 instance type for all nodes"
  type        = string
  default     = "t3.medium"
}

variable "ssh_public_key" {
  description = "SSH public key content for EC2 key pair"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into nodes"
  type        = string
  default     = "0.0.0.0/0"
}

variable "volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "kubernetes_version" {
  description = "Kubernetes version for kubeadm (major.minor)"
  type        = string
  default     = "1.29"
}
