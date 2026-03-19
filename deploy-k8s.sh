#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# deploy-k8s.sh  —  Build, push, and roll out UI and/or API to EKS
#
# USAGE
#   ./deploy-k8s.sh [OPTIONS]
#
# OPTIONS
#   --api            Deploy API only  (mock-api)
#   --ui             Deploy UI only   (mock-web)
#   --skip-build     Skip Docker build/push; restart existing pods only
#   --tag <tag>      Docker image tag  (default: latest)
#   --cluster <name> EKS cluster name (default: hrms-cluster)
#   --region <name>  AWS region        (default: us-east-1)
#   --username <u>   Docker Hub username (default: DOCKERHUB_USERNAME env var)
#
# Without --api or --ui, both are deployed.
#
# EXAMPLES
#   DOCKERHUB_USERNAME=zamamb ./deploy-k8s.sh
#   DOCKERHUB_USERNAME=zamamb ./deploy-k8s.sh --ui
#   DOCKERHUB_USERNAME=zamamb ./deploy-k8s.sh --api --tag v1.2.0
#   ./deploy-k8s.sh --skip-build --api
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
DEPLOY_API=false
DEPLOY_UI=false
SKIP_BUILD=false
IMAGE_TAG="${IMAGE_TAG:-latest}"
CLUSTER="${EKS_CLUSTER:-hrms-cluster}"
REGION="${AWS_REGION:-us-east-1}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api)          DEPLOY_API=true ;;
    --ui)           DEPLOY_UI=true ;;
    --skip-build)   SKIP_BUILD=true ;;
    --tag)          IMAGE_TAG="$2"; shift ;;
    --cluster)      CLUSTER="$2";   shift ;;
    --region)       REGION="$2";    shift ;;
    --username)     DOCKERHUB_USERNAME="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# Default: deploy both when neither flag is given
if ! $DEPLOY_API && ! $DEPLOY_UI; then
  DEPLOY_API=true
  DEPLOY_UI=true
fi

# ── Logging helpers ───────────────────────────────────────────────────────────
info()    { echo ""; echo "==> $*"; }
ok()      { echo "    [ok]  $*"; }
section() {
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  printf  "│  %-61s│\n" "$*"
  echo "└─────────────────────────────────────────────────────────────┘"
}

# ── Dependency checks ─────────────────────────────────────────────────────────
need() {
  command -v "$1" &>/dev/null && return
  echo "ERROR: '$1' is required but not found." >&2
  exit 1
}
need docker
need kubectl
need aws

if ! $SKIP_BUILD && [[ -z "$DOCKERHUB_USERNAME" ]]; then
  echo "ERROR: DOCKERHUB_USERNAME is not set. Pass --username or export DOCKERHUB_USERNAME." >&2
  exit 1
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│           deploy-k8s.sh  —  EKS Deployment                  │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "  Cluster  : $CLUSTER ($REGION)"
echo "  Tag      : $IMAGE_TAG"
$DEPLOY_API  && echo "  API      : zamamb/mock-api:$IMAGE_TAG  →  mock-api/mock-api"
$DEPLOY_UI   && echo "  UI       : zamamb/mock-web:$IMAGE_TAG  →  mock-web/mock-web"
$SKIP_BUILD  && echo "  Mode     : skip-build (restart pods only)"

# ── Phase 1: Build & push images ──────────────────────────────────────────────
if ! $SKIP_BUILD; then
  if $DEPLOY_API; then
    section "Build & Push  —  mock-api"
    (
      cd "$SCRIPT_DIR/api"
      DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME" IMAGE_TAG="$IMAGE_TAG" bash deploy.sh
    )
    ok "mock-api image pushed"
  fi

  if $DEPLOY_UI; then
    section "Build & Push  —  mock-web"
    (
      cd "$SCRIPT_DIR/ui"
      DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME" IMAGE_TAG="$IMAGE_TAG" bash deploy.sh
    )
    ok "mock-web image pushed"
  fi
fi

# ── Phase 2: Kubeconfig ───────────────────────────────────────────────────────
info "Configuring kubectl for cluster '$CLUSTER'..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" 2>&1 | grep -v "^$" || true
ok "kubeconfig updated"

# ── Phase 3: Rollout restarts ─────────────────────────────────────────────────
rollout() {
  local name="$1" namespace="$2"
  section "Rolling out  —  $name"
  kubectl rollout restart deployment/"$name" -n "$namespace"
  echo ""
  kubectl rollout status deployment/"$name" -n "$namespace" --timeout=180s
  ok "$name rollout complete"
}

if $DEPLOY_API; then
  rollout mock-api mock-api
fi

if $DEPLOY_UI; then
  rollout mock-web mock-web
fi

# ── Phase 4: Verify pods ──────────────────────────────────────────────────────
info "Pod status:"
echo ""
if $DEPLOY_API; then
  kubectl get pods -n mock-api -l app=mock-api \
    --no-headers \
    -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,IMAGE:.spec.containers[0].image"
fi
if $DEPLOY_UI; then
  kubectl get pods -n mock-web -l app=mock-web \
    --no-headers \
    -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,IMAGE:.spec.containers[0].image"
fi

echo ""
echo "==> Deployment complete."
