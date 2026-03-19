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
  value       = length(aws_apigatewayv2_domain_name.main) > 0 ? aws_apigatewayv2_domain_name.main[0].domain_name_configuration[0].target_domain_name : "Custom domain not configured"
}

output "acm_certificate_arn_used" {
  description = "ACM certificate ARN attached to the API Gateway custom domain"
  value       = var.custom_domain_name != "" ? local.resolved_certificate_arn : "No custom domain configured"
}

output "ui_endpoint" {
  description = "API Gateway endpoint for the Next.js UI"
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/web/"
}

output "example_requests" {
  description = "Example curl commands to test the full traffic flow"
  value       = <<-EOT
    # Default endpoint (no custom domain):
    curl ${aws_apigatewayv2_api.main.api_endpoint}/mock/api/users
    curl ${aws_apigatewayv2_api.main.api_endpoint}/mock/api/products

    # If custom domain is configured:
    # curl https://${var.custom_domain_name}/mock/api/users
  EOT
}
