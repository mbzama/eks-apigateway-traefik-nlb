#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# import.sh  —  Auto-discover and import provisioned AWS resources
#
# TOOL: terraformer (https://github.com/GoogleCloudPlatform/terraformer)
#   An open-source reverse-Terraform tool by Google that scans a live AWS
#   account and exports resource IDs and attributes into Terraform state files.
#   This script reads those state files via 'jq' to drive dynamic
#   'terraform import' commands, replacing the hardcoded IDs in cleanup.sh.
#
# USAGE
#   ./import.sh              # discover and import all resources
#   ./import.sh --dry-run    # print import commands without executing
#
# INSTALL DEPENDENCIES
#   terraformer:
#     macOS:  brew install terraformer
#     Linux:  GOARCH="$(uname -m | sed s/x86_64/amd64/)" && \
#             curl -L "https://github.com/GoogleCloudPlatform/terraformer/releases/latest/download/terraformer-all-linux-${GOARCH}" \
#               -o /usr/local/bin/terraformer && chmod +x /usr/local/bin/terraformer
#   jq:      brew install jq  |  apt install jq
#   aws-cli: https://aws.amazon.com/cli/
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ─────────────────────────────────────────────────────────────────────────────
# ACM_DOMAIN  —  the wildcard domain this script manages
# ─────────────────────────────────────────────────────────────────────────────
ACM_DOMAIN="*.zamait.in"

# ── Read configuration from terraform.tfvars ─────────────────────────────────
tfvar() {
  grep "^${1}\s*=" terraform.tfvars \
    | sed 's/[^=]*=\s*"\?\([^"#]*\)"\?\s*$/\1/' \
    | tr -d ' \r'
}

REGION="$(tfvar aws_region)"
CLUSTER="$(tfvar cluster_name)"
NODE_GROUP="$(tfvar node_group_name)"
GW_NAME="$(tfvar api_gateway_name)"
TRAEFIK_NS="$(tfvar traefik_namespace)"
APP_NS="$(tfvar app_namespace)"
UI_NS="$(tfvar ui_namespace)"
CLUSTER_ROLE="${CLUSTER}-cluster-role"
NODE_ROLE="${CLUSTER}-node-role"

# ── Logging helpers ───────────────────────────────────────────────────────────
info()  { echo ""; echo "==> $*"; }
log()   { echo "    $*"; }
skip()  { echo "    [skip]  $1  (not found)"; }
ok()    { echo "    [ok]    $*"; }
warn()  { echo "    [warn]  $*"; }

# ── Dependency checks ─────────────────────────────────────────────────────────
need() {
  command -v "$1" &>/dev/null && return
  echo ""
  echo "ERROR: '$1' is required but not found."
  case "$1" in
    terraformer)
      echo "  macOS:  brew install terraformer"
      echo "  Linux:  see https://github.com/GoogleCloudPlatform/terraformer#installation"
      ;;
    jq)  echo "  Install: brew install jq  or  apt install jq" ;;
    aws) echo "  Install: https://aws.amazon.com/cli/" ;;
  esac
  exit 1
}

need terraformer
need jq
need aws

# ── Temp workspace (cleaned up on exit) ──────────────────────────────────────
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Path to terraformer-generated state file for a given resource type
tf_state() { echo "$WORK/generated/aws/${1}/terraform.tfstate"; }

# ── Run terraformer for a resource group ─────────────────────────────────────
scan() {
  local label="$1" resources="$2" filter="${3:-}"
  echo ""
  echo "  [scan] $label  →  $resources"
  [[ -n "$filter" ]] && echo "         filter: $filter"
  local args=(
    import aws
    --resources="$resources"
    --regions="$REGION"
    --compact
    --path-output "$WORK"
  )
  [[ -n "$filter" ]] && args+=("--filter=$filter")
  (
    cd "$WORK"
    terraformer "${args[@]}" 2>&1 \
      | grep -Ev "^(time=|level=info|level=warning)" \
      | sed 's/^/    /' \
      || true
  )
}

# ── jq helpers ────────────────────────────────────────────────────────────────
# Get Nth resource ID of a given type from a terraformer state file
get_id() {
  local file="$1" type="$2" n="${3:-0}"
  [[ -f "$file" ]] || { echo ""; return; }
  jq -r --arg t "$type" --argjson n "$n" \
    '[.resources[] | select(.type==$t) | .instances[0].attributes.id] | .[$n] // ""' \
    "$file" 2>/dev/null || echo ""
}

# Get all IDs of a given type from a state file
get_ids() {
  local file="$1" type="$2"
  [[ -f "$file" ]] || return 0
  jq -r --arg t "$type" \
    '.resources[] | select(.type==$t) | .instances[0].attributes.id' \
    "$file" 2>/dev/null || true
}

# Get a specific attribute of the Nth resource
get_attr() {
  local file="$1" type="$2" attr="$3" n="${4:-0}"
  [[ -f "$file" ]] || { echo ""; return; }
  jq -r --arg t "$type" --arg a "$attr" --argjson n "$n" \
    '[.resources[] | select(.type==$t) | .instances[0].attributes[$a]] | .[$n] // ""' \
    "$file" 2>/dev/null || echo ""
}

# Get subnet IDs by Kubernetes role tag (elb=public, internal-elb=private)
get_subnets_by_role() {
  local file="$1" role="$2"
  [[ -f "$file" ]] || return 0
  jq -r --arg role "$role" \
    '.resources[] | select(.type=="aws_subnet")
     | select(
         (.instances[0].attributes.tags["kubernetes.io/role/\($role)"] // "") == "1"
       )
     | .instances[0].attributes.id' \
    "$file" 2>/dev/null || true
}

# Get route-table ID by Name tag
get_rt_by_name() {
  local file="$1" name_tag="$2"
  [[ -f "$file" ]] || { echo ""; return; }
  jq -r --arg n "$name_tag" \
    '.resources[] | select(.type=="aws_route_table")
     | select((.instances[0].attributes.tags.Name // "") == $n)
     | .instances[0].attributes.id' \
    "$file" 2>/dev/null | head -1 || echo ""
}

# ── AWS CLI helpers ───────────────────────────────────────────────────────────
# Route-table association ID for a given subnet + route-table pair
aws_rtassoc() {
  local rt_id="$1" subnet_id="$2"
  aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=route-table-id,Values=$rt_id" \
              "Name=association.subnet-id,Values=$subnet_id" \
    --query 'RouteTables[0].Associations[?SubnetId==`'"$subnet_id"'`].RouteTableAssociationId' \
    --output text 2>/dev/null | tr -d '\t ' || echo ""
}

# Security-group rule ID by SG, direction, and source/dest
aws_sgrule() {
  local sg_id="$1" is_egress="$2" filter="$3"
  aws ec2 describe-security-group-rules \
    --region "$REGION" \
    --filters "Name=group-id,Values=$sg_id" "$filter" \
    --query "SecurityGroupRules[?IsEgress==\`${is_egress}\`] | [0].SecurityGroupRuleId" \
    --output text 2>/dev/null | grep -v None || echo ""
}

# API Gateway v2 resource ID by name / parent API
aws_apigw_id() {
  local api_id="$1"
  aws apigatewayv2 get-apis \
    --region "$REGION" \
    --query "Items[?Name==\`$GW_NAME\`].ApiId" \
    --output text 2>/dev/null | grep -v None || echo ""
}

# ── Import helper ─────────────────────────────────────────────────────────────
tf_import() {
  local addr="$1" id="$2"
  if [[ -z "$id" || "$id" == "None" || "$id" == "null" ]]; then
    skip "$addr"
    return 0
  fi
  if $DRY_RUN; then
    echo "    terraform import -input=false '$addr' '$id'"
    return 0
  fi
  local out rc=0
  out="$(terraform import -input=false "$addr" "$id" 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "$addr  ←  $id"
  elif echo "$out" | grep -q "already managed by Terraform"; then
    log "[exists] $addr"
  else
    warn "$addr : $out"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  import.sh  —  powered by terraformer                       │"
echo "│  https://github.com/GoogleCloudPlatform/terraformer         │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "  Cluster  : $CLUSTER"
echo "  Region   : $REGION"
echo "  Gateway  : $GW_NAME"
$DRY_RUN && echo "  Mode     : DRY RUN — no state changes will be made"

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 0 — IMPORT ACM CERTIFICATE FROM PEM FILES
#
# Imports an externally-issued wildcard certificate (*.zamait.in) into ACM
# using three PEM files:
#   --certificate      The signed leaf/wildcard certificate  (cert.pem)
#   --private-key      The matching private key              (privkey.pem)
#   --certificate-chain  The CA / intermediate chain          (chain.pem)
#
# After a successful import the ARN is written back to terraform.tfvars so
# that api_gateway.tf picks it up without a data-source lookup.
# ══════════════════════════════════════════════════════════════════════════════
import_acm_cert() {
  echo ""
  echo "┌──────────────────────────────────────────────────────────────┐"
  echo "│  ACM Certificate Import  —  ${ACM_DOMAIN}$(printf '%*s' $((30 - ${#ACM_DOMAIN})) '')│"
  echo "└──────────────────────────────────────────────────────────────┘"

  # ── Prompt for file paths ────────────────────────────────────────────────
  read -r -p "  Certificate file  (cert.pem)   : " CERT_FILE
  read -r -p "  Private key file  (privkey.pem): " KEY_FILE
  read -r -p "  Chain file        (chain.pem)  : " CHAIN_FILE

  # ── Validate files exist ─────────────────────────────────────────────────
  for f in "$CERT_FILE" "$KEY_FILE" "$CHAIN_FILE"; do
    if [[ ! -f "$f" ]]; then
      echo ""
      echo "ERROR: File not found: $f"
      exit 1
    fi
  done

  if $DRY_RUN; then
    echo ""
    echo "    [dry-run] aws acm import-certificate \\"
    echo "      --certificate      file://$CERT_FILE \\"
    echo "      --private-key      file://$KEY_FILE \\"
    echo "      --certificate-chain file://$CHAIN_FILE \\"
    echo "      --region $REGION"
    echo "    [dry-run] terraform.tfvars  acm_certificate_arn  ← <imported-arn>"
    return 0
  fi

  # ── Check if a wildcard cert already exists and offer to re-import ────────
  EXISTING_ARN="$(aws acm list-certificates \
    --region "$REGION" \
    --query "CertificateSummaryList[?DomainName==\`${ACM_DOMAIN}\`].CertificateArn" \
    --output text 2>/dev/null | grep -v None | head -1 || echo "")"

  local import_args=(
    --certificate      "file://${CERT_FILE}"
    --private-key      "file://${KEY_FILE}"
    --certificate-chain "file://${CHAIN_FILE}"
    --region "$REGION"
  )

  if [[ -n "$EXISTING_ARN" ]]; then
    echo ""
    echo "  Found existing ACM cert for ${ACM_DOMAIN}:"
    echo "    $EXISTING_ARN"
    echo "  Re-importing (updating in-place)..."
    import_args+=(--certificate-arn "$EXISTING_ARN")
  else
    echo ""
    echo "  No existing cert found — importing new certificate..."
    import_args+=(--tags "Key=Name,Value=${ACM_DOMAIN}")
  fi

  # ── Import ────────────────────────────────────────────────────────────────
  IMPORTED_ARN="$(aws acm import-certificate "${import_args[@]}" \
    --query 'CertificateArn' --output text 2>&1)"

  if [[ "$IMPORTED_ARN" != arn:aws:acm:* ]]; then
    echo ""
    echo "ERROR: ACM import failed:"
    echo "  $IMPORTED_ARN"
    exit 1
  fi

  echo ""
  ok "Certificate imported: $IMPORTED_ARN"

  # ── Patch acm_certificate_arn in terraform.tfvars ─────────────────────────
  if grep -q '^acm_certificate_arn' terraform.tfvars; then
    sed -i.bak \
      "s|^acm_certificate_arn.*|acm_certificate_arn = \"${IMPORTED_ARN}\"|" \
      terraform.tfvars && rm -f terraform.tfvars.bak
  else
    echo "acm_certificate_arn = \"${IMPORTED_ARN}\"" >> terraform.tfvars
  fi

  echo "  terraform.tfvars  →  acm_certificate_arn updated"
}

info "ACM Certificate (${ACM_DOMAIN})..."
import_acm_cert

info "Initialising Terraform..."
terraform init -input=false -upgrade=false

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1 — DISCOVER RESOURCES WITH TERRAFORMER
# ══════════════════════════════════════════════════════════════════════════════
info "Scanning AWS account with terraformer (region: $REGION)..."

CLUSTER_TAG="kubernetes.io/cluster/${CLUSTER}"

# VPC, subnets, gateways, route tables — filter to this cluster's VPC
scan "VPC & networking" \
  "vpc,subnet,igw,nat,route_table" \
  "Name=tags.${CLUSTER_TAG}:Value=owned"

# Security groups — same cluster tag filter
scan "Security groups" \
  "sg" \
  "Name=tags.${CLUSTER_TAG}:Value=owned"

# IAM roles — filter by the two known role names
scan "IAM roles" \
  "iam_role" \
  "Name=name:Value=${CLUSTER_ROLE};${NODE_ROLE}"

# EKS cluster and node group
scan "EKS cluster" \
  "eks" \
  "Name=name:Value=${CLUSTER}"

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2 — EXTRACT IDs FROM TERRAFORMER STATE
# ══════════════════════════════════════════════════════════════════════════════
info "Extracting resource IDs from terraformer state..."

VPC_F="$(tf_state vpc)"
SUB_F="$(tf_state subnet)"
IGW_F="$(tf_state igw)"
NAT_F="$(tf_state nat)"
RT_F="$(tf_state route_table)"
SG_F="$(tf_state sg)"
IAM_F="$(tf_state iam_role)"
EKS_F="$(tf_state eks)"

# VPC
VPC_ID="$(get_id "$VPC_F" aws_vpc)"

# Internet Gateway + NAT + EIP
IGW_ID="$(get_id "$IGW_F" aws_internet_gateway)"
NAT_ID="$(get_id "$NAT_F" aws_nat_gateway)"
EIP_ID="$(get_attr "$NAT_F" aws_nat_gateway allocation_id)"

# Subnets (sorted: public by kubernetes.io/role/elb, private by internal-elb)
mapfile -t PUB_SUBS  < <(get_subnets_by_role "$SUB_F" elb)
mapfile -t PRIV_SUBS < <(get_subnets_by_role "$SUB_F" internal-elb)

# Route tables (identified by Name tag set in vpc.tf)
PUB_RT="$(get_rt_by_name  "$RT_F" "${CLUSTER}-public-rt")"
PRIV_RT="$(get_rt_by_name "$RT_F" "${CLUSTER}-private-rt")"

# Security groups — match by Name tag set in security_groups.tf
SG_CLUSTER="$(jq -r \
  '.resources[] | select(.type=="aws_security_group")
   | select((.instances[0].attributes.tags.Name // "") | test("eks-cluster-sg|cluster-sg"))
   | .instances[0].attributes.id' \
  "$SG_F" 2>/dev/null | head -1 || echo "")"

SG_NODES="$(jq -r \
  '.resources[] | select(.type=="aws_security_group")
   | select((.instances[0].attributes.tags.Name // "") | test("eks-nodes-sg|nodes-sg"))
   | .instances[0].attributes.id' \
  "$SG_F" 2>/dev/null | head -1 || echo "")"

SG_VPC_LINK="$(jq -r \
  '.resources[] | select(.type=="aws_security_group")
   | select((.instances[0].attributes.tags.Name // "") | test("vpc-link-sg|vpclink"))
   | .instances[0].attributes.id' \
  "$SG_F" 2>/dev/null | head -1 || echo "")"

# EKS
EKS_ARN="$(get_attr "$EKS_F" aws_eks_cluster arn)"
NODE_GROUP_ID="$(jq -r \
  '.resources[] | select(.type=="aws_eks_node_group")
   | .instances[0].attributes.id' \
  "$EKS_F" 2>/dev/null | head -1 || echo "")"

# OIDC provider (not in terraformer EKS output — look up via AWS CLI)
OIDC_URL="$(aws eks describe-cluster \
  --region "$REGION" --name "$CLUSTER" \
  --query 'cluster.identity.oidc.issuer' \
  --output text 2>/dev/null | sed 's|https://||' || echo "")"
ACCOUNT_ID="$(aws sts get-caller-identity \
  --query Account --output text 2>/dev/null || echo "")"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"

# Security group rule IDs (AWS CLI — derived resources not in terraformer state)
SGR_CLUSTER_INGRESS=""
SGR_NODES_SELF=""
SGR_NODES_INGRESS_CLUSTER=""
if [[ -n "$SG_CLUSTER" && -n "$SG_NODES" ]]; then
  # eks_cluster_ingress_nodes: ingress on cluster SG from nodes SG
  SGR_CLUSTER_INGRESS="$(aws ec2 describe-security-group-rules \
    --region "$REGION" \
    --filters "Name=group-id,Values=$SG_CLUSTER" \
              "Name=referenced-group-id,Values=$SG_NODES" \
    --query 'SecurityGroupRules[?IsEgress==`false`] | [0].SecurityGroupRuleId' \
    --output text 2>/dev/null | grep -v None || echo "")"

  # eks_nodes_self: self-referential ingress on nodes SG
  SGR_NODES_SELF="$(aws ec2 describe-security-group-rules \
    --region "$REGION" \
    --filters "Name=group-id,Values=$SG_NODES" \
              "Name=referenced-group-id,Values=$SG_NODES" \
    --query 'SecurityGroupRules[?IsEgress==`false`] | [0].SecurityGroupRuleId' \
    --output text 2>/dev/null | grep -v None || echo "")"

  # eks_nodes_ingress_cluster: ingress on nodes SG from cluster SG
  SGR_NODES_INGRESS_CLUSTER="$(aws ec2 describe-security-group-rules \
    --region "$REGION" \
    --filters "Name=group-id,Values=$SG_NODES" \
              "Name=referenced-group-id,Values=$SG_CLUSTER" \
    --query 'SecurityGroupRules[?IsEgress==`false`] | [0].SecurityGroupRuleId' \
    --output text 2>/dev/null | grep -v None || echo "")"
fi

# API Gateway v2 — AWS CLI (terraformer apigatewayv2 support is limited)
APIGW_API_ID="$(aws apigatewayv2 get-apis \
  --region "$REGION" \
  --query "Items[?Name==\`${GW_NAME}\`].ApiId" \
  --output text 2>/dev/null | grep -v None || echo "")"

APIGW_VPC_LINK_ID=""
APIGW_STAGE_ID=""
APIGW_INT_API_ID=""
APIGW_INT_UI_ID=""
APIGW_ROUTE_MOCK_ID=""
APIGW_ROUTE_WEB_ID=""
APIGW_LOG_GROUP="/aws/apigateway/${GW_NAME}"

if [[ -n "$APIGW_API_ID" ]]; then
  APIGW_VPC_LINK_ID="$(aws apigatewayv2 get-vpc-links \
    --region "$REGION" \
    --query "Items[0].VpcLinkId" \
    --output text 2>/dev/null | grep -v None || echo "")"

  APIGW_STAGE_ID="${APIGW_API_ID}/\$default"

  # Integrations
  mapfile -t INTEG_IDS < <(aws apigatewayv2 get-integrations \
    --region "$REGION" --api-id "$APIGW_API_ID" \
    --query 'Items[].IntegrationId' --output text 2>/dev/null \
    | tr '\t' '\n' | grep -v None || true)
  APIGW_INT_API_ID="${APIGW_API_ID}/${INTEG_IDS[0]:-}"
  APIGW_INT_UI_ID="${APIGW_API_ID}/${INTEG_IDS[1]:-}"

  # Routes
  mapfile -t ROUTE_IDS < <(aws apigatewayv2 get-routes \
    --region "$REGION" --api-id "$APIGW_API_ID" \
    --query 'Items[].RouteId' --output text 2>/dev/null \
    | tr '\t' '\n' | grep -v None || true)
  APIGW_ROUTE_MOCK_ID="${APIGW_API_ID}/${ROUTE_IDS[0]:-}"
  APIGW_ROUTE_WEB_ID="${APIGW_API_ID}/${ROUTE_IDS[1]:-}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 3 — IMPORT INTO TERRAFORM STATE
# ══════════════════════════════════════════════════════════════════════════════
info "Importing resources into Terraform state..."
echo ""

# ── VPC & networking ──────────────────────────────────────────────────────────
echo "  — VPC & networking"
tf_import "aws_vpc.main"                "$VPC_ID"
tf_import "aws_internet_gateway.main"   "$IGW_ID"
tf_import "aws_eip.nat"                 "$EIP_ID"
tf_import "aws_nat_gateway.main"        "$NAT_ID"
tf_import "aws_route_table.public"      "$PUB_RT"
tf_import "aws_route_table.private"     "$PRIV_RT"

for i in "${!PUB_SUBS[@]}"; do
  tf_import "aws_subnet.public[$i]"                  "${PUB_SUBS[$i]}"
  assoc="$(aws_rtassoc "$PUB_RT" "${PUB_SUBS[$i]}")"
  tf_import "aws_route_table_association.public[$i]" "$assoc"
done

for i in "${!PRIV_SUBS[@]}"; do
  tf_import "aws_subnet.private[$i]"                  "${PRIV_SUBS[$i]}"
  assoc="$(aws_rtassoc "$PRIV_RT" "${PRIV_SUBS[$i]}")"
  tf_import "aws_route_table_association.private[$i]" "$assoc"
done

# ── Security groups ───────────────────────────────────────────────────────────
echo ""
echo "  — Security groups"
tf_import "aws_security_group.eks_cluster"   "$SG_CLUSTER"
tf_import "aws_security_group.eks_nodes"     "$SG_NODES"
tf_import "aws_security_group.vpc_link"      "$SG_VPC_LINK"
tf_import "aws_security_group_rule.eks_cluster_ingress_nodes"  "$SGR_CLUSTER_INGRESS"
tf_import "aws_security_group_rule.eks_nodes_self"             "$SGR_NODES_SELF"
tf_import "aws_security_group_rule.eks_nodes_ingress_cluster"  "$SGR_NODES_INGRESS_CLUSTER"

# ── IAM ───────────────────────────────────────────────────────────────────────
echo ""
echo "  — IAM"
tf_import "aws_iam_role.eks_cluster"  "$CLUSTER_ROLE"
tf_import "aws_iam_role.eks_nodes"    "$NODE_ROLE"
tf_import "aws_iam_role_policy_attachment.eks_cluster_policy" \
  "${CLUSTER_ROLE}/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
tf_import "aws_iam_role_policy_attachment.eks_vpc_resource_controller" \
  "${CLUSTER_ROLE}/arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
tf_import "aws_iam_role_policy_attachment.eks_worker_node_policy" \
  "${NODE_ROLE}/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
tf_import "aws_iam_role_policy_attachment.eks_cni_policy" \
  "${NODE_ROLE}/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
tf_import "aws_iam_openid_connect_provider.eks"  "$OIDC_ARN"

# ── EKS ───────────────────────────────────────────────────────────────────────
echo ""
echo "  — EKS"
tf_import "aws_eks_cluster.main"     "$CLUSTER"
tf_import "aws_eks_node_group.main"  "${CLUSTER}:${NODE_GROUP}"

# ── API Gateway ───────────────────────────────────────────────────────────────
echo ""
echo "  — API Gateway v2"
tf_import "aws_apigatewayv2_api.main"                 "$APIGW_API_ID"
tf_import "aws_apigatewayv2_vpc_link.main"             "$APIGW_VPC_LINK_ID"
tf_import "aws_apigatewayv2_stage.default"             "$APIGW_STAGE_ID"
tf_import "aws_apigatewayv2_integration.traefik"       "$APIGW_INT_API_ID"
tf_import "aws_apigatewayv2_integration.traefik_ui"    "$APIGW_INT_UI_ID"
tf_import "aws_apigatewayv2_route.mock_proxy"          "$APIGW_ROUTE_MOCK_ID"
tf_import "aws_apigatewayv2_route.web_proxy"           "$APIGW_ROUTE_WEB_ID"
tf_import "aws_cloudwatch_log_group.api_gw"            "$APIGW_LOG_GROUP"

# ── Kubernetes & Helm (IDs are deterministic from config — no discovery needed)
echo ""
echo "  — Kubernetes & Helm"
tf_import "kubernetes_namespace.traefik"              "$TRAEFIK_NS"
tf_import "kubernetes_namespace.mock_api"             "$APP_NS"
tf_import "kubernetes_namespace.mock_web"             "$UI_NS"
tf_import "helm_release.traefik"                      "${TRAEFIK_NS}/traefik"
tf_import "kubernetes_deployment.mock_api"            "${APP_NS}/mock-api"
tf_import "kubernetes_deployment.mock_web"            "${UI_NS}/mock-web"
tf_import "kubernetes_service.mock_api"               "${APP_NS}/mock-api"
tf_import "kubernetes_service.mock_web"               "${UI_NS}/mock-web"
tf_import "kubernetes_manifest.mock_api_ingress_route" \
  "apiVersion=traefik.io/v1alpha1,kind=IngressRoute,namespace=${APP_NS},name=mock-api"
tf_import "kubernetes_manifest.mock_web_ingress_route" \
  "apiVersion=traefik.io/v1alpha1,kind=IngressRoute,namespace=${UI_NS},name=mock-web"

# ── Reconcile state with live attributes ─────────────────────────────────────
if ! $DRY_RUN; then
  info "Reconciling state with live AWS attributes (refresh-only apply)..."
  terraform apply -refresh-only -auto-approve
fi

echo ""
echo "==> Import complete."
$DRY_RUN && echo "    Re-run without --dry-run to apply."
