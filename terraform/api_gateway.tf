# ─────────────────────────────────────────────────────────────────────────────
# HTTP API (API Gateway v2)
#
# Protocol: HTTP (not REST / WebSocket)
# Type:     REGIONAL  – single-region endpoint in us-east-1
# CORS:     Not configured here; add if needed for browser clients.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "main" {
  name          = var.api_gateway_name
  protocol_type = "HTTP"
  description   = "HRMS HTTP API – routes via VPC Link to Traefik NLB"

  tags = {
    Name = var.api_gateway_name
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC Link
#
# Connects the API Gateway to resources inside the VPC.
# Subnets: private (worker nodes / NLB live here)
# Security group: only allows outbound port 80 to the VPC CIDR
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.cluster_name}-vpc-link"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = {
    Name = "${var.cluster_name}-vpc-link"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration – HTTP_PROXY via VPC Link → Traefik NLB Listener
#
# integration_uri:    NLB Listener ARN (required for VPC Link + NLB combo)
# integration_method: ANY  – forwards all HTTP methods unchanged
# connection_type:    VPC_LINK
#
# Path rewrite: strips the /mock prefix so that a request to
#   /mock/analytics/health  →  /analytics/health  arrives at Traefik.
# Traefik then matches IngressRoute: Host(app_host) && PathPrefix(/api)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "traefik" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  # The NLB listener ARN is resolved from the data source in traefik.tf
  integration_uri = data.aws_lb_listener.traefik_http.arn

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.main.id

  # Strip the /mock prefix: /mock/{proxy+} → /{proxy+}
  # Also set the Host header so Traefik IngressRoute can match it
  request_parameters = {
    "overwrite:path"        = "/$request.path.proxy"
    "overwrite:header.Host" = var.app_host
  }

  # Forward the Host header that Traefik uses for routing
  # API GW HTTP APIs pass through headers by default; set explicitly for clarity.
  payload_format_version = "1.0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Route – ANY /mock/{proxy+}
#
# Matches any HTTP method and any path under /mock/.
# Example: GET /mock/api/users  →  integration above  →  Traefik  →  mock-api
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "mock_proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /mock/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.traefik.id}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration – UI (Next.js)
#
# Same VPC Link / NLB as the API integration, but sets a different Host header
# so Traefik routes to the mock-web service instead of mock-api.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "traefik_ui" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  integration_uri = data.aws_lb_listener.traefik_http.arn

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.main.id

  # Do NOT rewrite the path — Next.js basePath '/web' needs the full path.
  # Only override the Host header so Traefik routes to the UI service.
  request_parameters = {
    "overwrite:header.Host" = var.ui_host
  }

  payload_format_version = "1.0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Routes – /web and /web/{proxy+}
#
# Two routes are needed because {proxy+} requires at least one segment:
#   ANY /web         → matches exactly /web  (Next.js basePath root)
#   ANY /web/{proxy+} → matches /web/products, /web/_next/static/…, etc.
#
# The full path is forwarded unchanged so Next.js (basePath '/web') can
# match its own routes and serve static assets at /web/_next/static/…
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "web_root" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /web"
  target    = "integrations/${aws_apigatewayv2_integration.traefik_ui.id}"
}

resource "aws_apigatewayv2_route" "web_proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /web/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.traefik_ui.id}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage – $default  (auto-deploy enabled)
#
# The $default stage is the implicit catch-all stage for HTTP APIs.
# With auto_deploy = true, every route/integration change is published
# immediately without a manual deployment step.
#
# Access logging: writes a structured JSON log per request to CloudWatch.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.api_gateway_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.api_gateway_name}-logs"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      protocol       = "$context.protocol"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  tags = {
    Name = "${var.api_gateway_name}-default-stage"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ACM Certificate Lookup  (used only when custom_domain_name is set)
#
# If acm_certificate_arn is left empty, Terraform looks up the certificate by
# domain in ACM.  Set acm_certificate_domain = "*.zamait.in" to find the
# wildcard cert that covers dev.zamait.in (and any other subdomain).
# Falls back to custom_domain_name when acm_certificate_domain is not set.
# Supply acm_certificate_arn explicitly in tfvars to skip the lookup entirely.
# ─────────────────────────────────────────────────────────────────────────────
locals {
  # Domain used for the ACM data-source lookup; wildcard takes precedence.
  cert_lookup_domain = var.acm_certificate_domain != "" ? var.acm_certificate_domain : var.custom_domain_name
}

data "aws_acm_certificate" "api_gateway" {
  count = var.custom_domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0

  domain      = local.cert_lookup_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  # Use the explicitly-provided ARN when set; fall back to the data-source lookup.
  resolved_certificate_arn = (
    var.acm_certificate_arn != ""
    ? var.acm_certificate_arn
    : (var.custom_domain_name != "" ? data.aws_acm_certificate.api_gateway[0].arn : "")
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Custom Domain  (optional)
#
# Set custom_domain_name in tfvars to enable a vanity domain.
# Either supply acm_certificate_arn directly, or leave it empty and let the
# data source above find the ISSUED certificate for that domain automatically.
# After apply, create a CNAME or ALIAS record in Route53 pointing to the
# api_gateway_domain_name output value.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_domain_name" "main" {
  count = var.custom_domain_name != "" ? 1 : 0

  domain_name = var.custom_domain_name

  domain_name_configuration {
    certificate_arn = local.resolved_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = {
    Name = var.custom_domain_name
  }
}

resource "aws_apigatewayv2_api_mapping" "main" {
  count = var.custom_domain_name != "" ? 1 : 0

  api_id      = aws_apigatewayv2_api.main.id
  domain_name = aws_apigatewayv2_domain_name.main[0].id
  stage       = aws_apigatewayv2_stage.default.id
}
