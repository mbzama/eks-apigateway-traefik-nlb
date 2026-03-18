#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
IMAGE_NAME="${IMAGE_NAME:-mock-api}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# ── Validation ────────────────────────────────────────────────────────────────
if [[ -z "$DOCKERHUB_USERNAME" ]]; then
  echo "ERROR: DOCKERHUB_USERNAME is not set." >&2
  exit 1
fi

FULL_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME"

# ── Build & Push ──────────────────────────────────────────────────────────────
# --platform linux/amd64: EKS t3.medium nodes are x86_64; building on Apple
# Silicon (arm64) without this flag produces an arm64 image that fails to
# schedule with "no match for platform in manifest: not found".
echo "Building and pushing image: $FULL_IMAGE:$IMAGE_TAG ..."
docker buildx build --platform linux/amd64 --target production \
  -t "$FULL_IMAGE:$IMAGE_TAG" \
  -t "$FULL_IMAGE:latest" \
  --push \
  .

echo "Done. Image pushed to Docker Hub: $FULL_IMAGE:$IMAGE_TAG"
