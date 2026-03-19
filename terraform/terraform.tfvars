# ─────────────────────────────────────────────────────────────────────────────
# terraform.tfvars  –  override variable defaults for this deployment
# ─────────────────────────────────────────────────────────────────────────────

# General
aws_region  = "us-east-1"
environment = "learning"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# EKS Cluster
cluster_name    = "hrms-cluster"
cluster_version = "1.31"

# EKS Node Group
node_group_name    = "hrms-ng-2"
node_instance_type = "t3.medium"
node_desired_size  = 1
node_min_size      = 1
node_max_size      = 1
node_disk_size     = 20

# Traefik
traefik_namespace     = "test-system"
traefik_chart_version = "26.1.0"
nlb_wait_seconds      = 120

# Application
app_namespace = "mock-api"
app_replicas  = 1
app_host      = "api.app-dev.example.com"
app_image = "zamamb/mock-api:latest"

# UI
ui_namespace = "mock-web"
ui_image     = "zamamb/mock-web:latest"
ui_replicas  = 1
ui_host      = "web.app-dev.example.com"

# API Gateway
api_gateway_name       = "hrms-api-gateway"
custom_domain_name     = "dev.zamait.in"
acm_certificate_domain = "*.zamait.in"   # wildcard cert covers dev.zamait.in
acm_certificate_arn    = "arn:aws:acm:us-east-1:608283508317:certificate/f8d2b151-8f46-47ca-b9e0-506caffaf392"
