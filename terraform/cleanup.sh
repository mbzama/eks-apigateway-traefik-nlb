#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# cleanup.sh  —  Destroy the full EKS + Traefik + API Gateway stack
#
# Three-stage destroy mirrors the three-stage create in create.sh:
#
#   Stage 1: Destroy API Gateway resources first.
#            The integrations reference data.aws_lb_listener.traefik_http.
#            If the NLB is gone before these are destroyed, Terraform's refresh
#            phase fails and API Gateway resources are left orphaned in AWS.
#
#   Stage 2: Destroy all Kubernetes and Helm resources.
#            Removing the Traefik LoadBalancer Service triggers the K8s cloud
#            controller to delete the AWS NLB.  This must happen before the
#            VPC is destroyed, otherwise AWS returns a DependencyViolation
#            error because the NLB's ENIs are still attached to the subnets.
#
#   Stage 3: Full terraform destroy for all remaining AWS resources
#            (EKS cluster, node group, VPC, IAM roles, ECR, etc.)
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> [init] Initialising Terraform (downloads providers, connects to backend)..."
terraform init

echo ""
echo "==> [import] Building Terraform state from live AWS resources..."
# Delegates resource discovery and import to import.sh, which uses terraformer
# to dynamically look up all resource IDs rather than relying on hardcoded values.
bash "$SCRIPT_DIR/import.sh"

echo ""
echo "==> [stage 1] Destroying API Gateway resources (before NLB is removed)..."
# These resources reference data.aws_lb_listener.traefik_http (the NLB listener ARN).
# They must be destroyed before the NLB is deleted, otherwise the data-source
# refresh in the final `terraform destroy` will fail with a "not found" error and
# leave API Gateway resources orphaned in AWS.
terraform destroy \
  -target=aws_apigatewayv2_api_mapping.main \
  -target=aws_apigatewayv2_domain_name.main \
  -target=aws_apigatewayv2_stage.default \
  -target=aws_apigatewayv2_route.mock_proxy \
  -target=aws_apigatewayv2_route.web_proxy \
  -target=aws_apigatewayv2_integration.traefik \
  -target=aws_apigatewayv2_integration.traefik_ui \
  -target=aws_apigatewayv2_vpc_link.main \
  -target=aws_apigatewayv2_api.main \
  -target=aws_cloudwatch_log_group.api_gw \
  -auto-approve

echo ""
echo "==> [stage 2] Destroying Kubernetes workloads and Traefik (triggers NLB deletion)..."
terraform destroy \
  -target=kubernetes_manifest.mock_api_ingress_route \
  -target=kubernetes_manifest.mock_web_ingress_route \
  -target=kubernetes_deployment.mock_api \
  -target=kubernetes_deployment.mock_web \
  -target=kubernetes_service.mock_api \
  -target=kubernetes_service.mock_web \
  -target=helm_release.traefik \
  -target=kubernetes_namespace.mock_api \
  -target=kubernetes_namespace.mock_web \
  -target=kubernetes_namespace.traefik \
  -auto-approve

# The NLB is deleted asynchronously by the K8s cloud controller after the
# LoadBalancer Service is removed.  Wait before destroying the VPC to avoid
# a DependencyViolation error.
echo ""
echo "==> Waiting 60s for the AWS NLB to be fully deprovisioned..."
sleep 60

echo ""
echo "==> [stage 3] Destroying remaining AWS resources (EKS, VPC, IAM)..."
terraform destroy -auto-approve

echo ""
echo "==> Cleanup complete."
