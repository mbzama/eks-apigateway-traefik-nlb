# ─────────────────────────────────────────────────────────────────────────────
# EKS Outputs
# ─────────────────────────────────────────────────────────────────────────────
output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.main.version
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Identity Provider (for IRSA)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# Networking Outputs
# ─────────────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets (worker nodes)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of public subnets (NAT Gateway)"
  value       = aws_subnet.public[*].id
}

# ─────────────────────────────────────────────────────────────────────────────
# ECR Outputs
# ─────────────────────────────────────────────────────────────────────────────
output "ecr_repository_url" {
  description = "ECR repository URL for the mock-api image"
  value       = aws_ecr_repository.mock_api.repository_url
}

output "ecr_push_commands" {
  description = "Commands to authenticate, build, tag, and push the mock-api image"
  value       = <<-EOT
    # 1. Authenticate Docker to ECR
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin \
      ${split("/", aws_ecr_repository.mock_api.repository_url)[0]}

    # 2. Build the image
    docker build -t mock-api ../api

    # 3. Tag
    docker tag mock-api:latest ${aws_ecr_repository.mock_api.repository_url}:latest

    # 4. Push
    docker push ${aws_ecr_repository.mock_api.repository_url}:latest

    # 5. Update app_image in terraform.tfvars, then re-run:
    #    terraform apply
  EOT
}

# ─────────────────────────────────────────────────────────────────────────────
# Traefik / NLB Outputs
# ─────────────────────────────────────────────────────────────────────────────
output "traefik_nlb_dns" {
  description = "Internal NLB DNS name created by the Traefik LoadBalancer Service"
  value       = data.aws_lb.traefik.dns_name
}

output "traefik_nlb_arn" {
  description = "ARN of the internal Traefik NLB"
  value       = data.aws_lb.traefik.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# API Gateway Outputs
# ─────────────────────────────────────────────────────────────────────────────
output "api_gateway_id" {
  description = "HTTP API Gateway ID"
  value       = aws_apigatewayv2_api.main.id
}

output "api_gateway_endpoint" {
  description = "Default invoke URL for the $default stage (no custom domain)"
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/mock"
}

output "api_gateway_domain_name" {
  description = "Regional domain name to CNAME/ALIAS for the custom domain (if configured)"
  value       = var.custom_domain_name != "" ? aws_apigatewayv2_domain_name.main[0].domain_name_configuration[0].target_domain_name : "Custom domain not configured"
}

output "example_requests" {
  description = "Example curl commands to test the full traffic flow"
  value       = <<-EOT
    # Default endpoint (no custom domain):
    curl ${aws_apigatewayv2_api.main.api_endpoint}/mock/api/users \
      -H "Host: ${var.app_host}"

    curl ${aws_apigatewayv2_api.main.api_endpoint}/mock/api/products \
      -H "Host: ${var.app_host}"

    # If custom domain is configured:
    # curl https://${var.custom_domain_name}/mock/api/users
  EOT
}
