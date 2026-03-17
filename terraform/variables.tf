# ─────────────────────────────────────────────────────────────────────────────
# General
# ─────────────────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (used in tags and naming)"
  type        = string
  default     = "learning"
}

# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ; used by the NAT Gateway and NLB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ; EKS worker nodes live here)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster
# ─────────────────────────────────────────────────────────────────────────────
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "hrms-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Node Group
# ─────────────────────────────────────────────────────────────────────────────
variable "node_group_name" {
  description = "Name of the EKS managed node group"
  type        = string
  default     = "hrms-ng-2"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for each worker node"
  type        = number
  default     = 20
}

# ─────────────────────────────────────────────────────────────────────────────
# Traefik
# ─────────────────────────────────────────────────────────────────────────────
variable "traefik_namespace" {
  description = "Kubernetes namespace where Traefik is installed"
  type        = string
  default     = "test-system"
}

variable "traefik_chart_version" {
  description = "Traefik Helm chart version"
  type        = string
  default     = "26.1.0"
}

variable "nlb_wait_seconds" {
  description = "Seconds to wait after Traefik is deployed before looking up the NLB ARN"
  type        = number
  default     = 120
}

# ─────────────────────────────────────────────────────────────────────────────
# Application
# ─────────────────────────────────────────────────────────────────────────────
variable "app_namespace" {
  description = "Kubernetes namespace for the NestJS mock-api application"
  type        = string
  default     = "mock-api"
}

variable "app_image" {
  description = "Full container image URI for the NestJS app (e.g. <account>.dkr.ecr.us-east-1.amazonaws.com/mock-api:latest)"
  type        = string
  # No default – must be set after building and pushing to ECR.
  # Set this in terraform.tfvars once the image is pushed.
  default = "placeholder/mock-api:latest"
}

variable "app_replicas" {
  description = "Number of NestJS pod replicas"
  type        = number
  default     = 1
}

variable "app_host" {
  description = "Host header value that Traefik uses to route traffic to the mock-api (e.g. api.app-dev.example.com)"
  type        = string
  default     = "api.app-dev.example.com"
}

# ─────────────────────────────────────────────────────────────────────────────
# API Gateway
# ─────────────────────────────────────────────────────────────────────────────
variable "api_gateway_name" {
  description = "Name of the HTTP API Gateway"
  type        = string
  default     = "hrms-api-gateway"
}

variable "custom_domain_name" {
  description = "Custom domain name for the API Gateway (leave empty to skip domain mapping)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the custom domain (required when custom_domain_name is set)"
  type        = string
  default     = ""
}
