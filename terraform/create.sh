#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# create.sh  —  Provision the full EKS + Traefik + API Gateway stack
#
# Three-stage apply is required because:
#   Stage 1: EKS cluster must exist before the Kubernetes/Helm providers
#            can be initialised.
#   Stage 2: Traefik Helm chart must be installed before the IngressRoute
#            CRD is available (used by the app and UI manifests).
#   Stage 3: Full apply — remaining resources (apps, API Gateway, etc.)
# ─────────────────────────────────────────────────────────────────────────────

echo "==> [init] Initialising Terraform..."
terraform init

echo ""
echo "==> [stage 1] Creating EKS cluster (VPC, subnets, NAT gateway, IAM, control plane)..."
terraform apply \
  -target=aws_eks_cluster.main \
  -target=aws_nat_gateway.main \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -auto-approve

echo ""
echo "==> [stage 2] Deploying Traefik + node group (installs IngressRoute CRD)..."
terraform apply -target=helm_release.traefik -auto-approve

echo ""
echo "==> [stage 3] Applying remaining resources (apps, API Gateway, IngressRoutes)..."
terraform apply -auto-approve

echo ""
echo "==> Done. Outputs:"
terraform output
